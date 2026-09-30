#!/usr/bin/env bash
# FRAMZ OS — загрузка ISO в QEMU и снимки экрана.
#
# Проверяет, что образ реально стартует и доходит до установщика — на двух
# прошивках: BIOS (SeaBIOS) и UEFI (OVMF). Без аппаратного ускорения (tcg),
# поэтому загрузка идёт медленно: снимки делаем раз в 5 минут.
#
# Использование:
#   bash scripts/iso-qemu-boot.sh ISO ПРОШИВКА МИНУТЫ КАТАЛОГ_ОТЧЁТА ИМЯ_ЗАПУСКА
#
#   ПРОШИВКА — bios или uefi
#   снимки: <каталог>/iso-boot-<имя>-<прошивка>-<номер>.png
#
# Важно: скрипт намеренно НЕ завершается с ошибкой из-за одного неудачного
# снимка — его задача собрать отчёт. Провал загрузки виден в отчёте.
set -uo pipefail

ISO="${1:?укажи путь к ISO}"
FIRMWARE="${2:-bios}"
MINUTES="${3:-15}"
OUTDIR="${4:-ci-logs}"
TAG="${5:-локально}"

[ -f "${ISO}" ] || { echo "нет файла: ${ISO}"; exit 1; }
case "${FIRMWARE}" in bios|uefi) ;; *) echo "прошивка должна быть bios или uefi"; exit 1 ;; esac
mkdir -p "${OUTDIR}"

LOG="${OUTDIR}/iso-boot-${TAG}-${FIRMWARE}.txt"
SOCK="/tmp/qemu-${FIRMWARE}-monitor.sock"
SERIAL="/tmp/qemu-${FIRMWARE}-serial.log"
QERR="/tmp/qemu-${FIRMWARE}-qemu.log"
rm -f "${SOCK}" "${SERIAL}" "${QERR}"
SHOTS=$((MINUTES / 5)); [ "${SHOTS}" -lt 1 ] && SHOTS=1

{
  echo "=== Загрузка FRAMZ OS в QEMU: прошивка ${FIRMWARE} ==="
  date -u +"начало: %Y-%m-%d %H:%M UTC"
  echo "образ: ${ISO} ($(( $(stat -c%s "${ISO}") / 1048576 )) МБ)"
  echo "снимки: каждые 5 мин, всего ${SHOTS} (${MINUTES} мин), без KVM"
  echo
} > "${LOG}"

# ── Аргументы загрузки под выбранную прошивку ───────────────────────────────
FW_ARGS=()
if [ "${FIRMWARE}" = "uefi" ]; then
  OVMF_CODE="$(ls /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd 2>/dev/null | head -1)"
  if [ -z "${OVMF_CODE}" ]; then
    echo "нет файлов OVMF (пакет ovmf) — загрузку UEFI пропускаем" | tee -a "${LOG}"
    exit 0
  fi
  case "${OVMF_CODE}" in
    */OVMF.fd) FW_ARGS=(-bios "${OVMF_CODE}") ;;
    *)
      VARS_SRC="$(dirname "${OVMF_CODE}")/OVMF_VARS_4M.fd"
      [ -f "${VARS_SRC}" ] || VARS_SRC="$(dirname "${OVMF_CODE}")/OVMF_VARS.fd"
      cp "${VARS_SRC}" /tmp/framz-OVMF_VARS.fd
      FW_ARGS=(-drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" -drive "if=pflash,format=raw,file=/tmp/framz-OVMF_VARS.fd")
      ;;
  esac
  echo "UEFI: ${OVMF_CODE}" | tee -a "${LOG}"
else
  echo "BIOS: SeaBIOS (по умолчанию)" | tee -a "${LOG}"
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "нет qemu-system-x86_64 — нужен пакет qemu-system-x86" | tee -a "${LOG}"
  exit 0
fi

qemu-system-x86_64 \
  -machine q35 -m 4096 -smp 4 -accel tcg \
  "${FW_ARGS[@]}" \
  -drive "file=${ISO},media=cdrom,readonly=on" \
  -boot d -display none -vnc none \
  -monitor "unix:${SOCK},server,nowait" \
  -serial "file:${SERIAL}" \
  > "${QERR}" 2>&1 &
QPID=$!
echo "QEMU запущен (pid ${QPID})" | tee -a "${LOG}"

# Ждём появления сокета монитора: если QEMU упал, здесь это станет видно
for _ in $(seq 1 30); do
  [ -S "${SOCK}" ] && break
  sleep 1
done
if [ ! -S "${SOCK}" ]; then
  echo "ВНИМАНИЕ: монитор QEMU не поднялся — вот что сказал QEMU:" | tee -a "${LOG}"
  tail -20 "${QERR}" 2>/dev/null | tee -a "${LOG}"
  kill "${QPID}" 2>/dev/null || true
  exit 0
fi
echo "монитор готов: ${SOCK}" | tee -a "${LOG}"

# shot <номер снимка>
shot() {
  local n="$1"
  local ppm="/tmp/boot-${FIRMWARE}-${n}.ppm"
  local out
  out="$(python3 scripts/iso-qemu-shot.py "${SOCK}" "${n}" "${ppm}" 2>&1 | tr -d '\r' | grep -v '^(qemu)' || true)"
  echo "--- снимок ${n} ---" | tee -a "${LOG}"
  echo "${out}" | grep -E 'VM status|снимок записан|монитор недоступен|не создан' | tee -a "${LOG}" || true
  if [ -f "${ppm}" ]; then
    if convert "${ppm}" "${OUTDIR}/iso-boot-${TAG}-${FIRMWARE}-${n}.png" 2>/dev/null; then
      echo "файл: iso-boot-${TAG}-${FIRMWARE}-${n}.png ($(stat -c%s "${OUTDIR}/iso-boot-${TAG}-${FIRMWARE}-${n}.png") байт)" | tee -a "${LOG}"
    else
      cp "${ppm}" "${OUTDIR}/iso-boot-${TAG}-${FIRMWARE}-${n}.ppm"
      echo "без конвертера, оставлен ppm" | tee -a "${LOG}"
    fi
  else
    echo "снимок ${n} не получился" | tee -a "${LOG}"
  fi
}

for i in $(seq 1 "${SHOTS}"); do
  sleep 300
  shot "${i}"
done

echo | tee -a "${LOG}"
echo "--- последние строки последовательного порта ---" | tee -a "${LOG}"
if [ -s "${SERIAL}" ]; then tail -20 "${SERIAL}" | tee -a "${LOG}"; else echo "(пусто — установщик графический)" | tee -a "${LOG}"; fi
echo "--- QEMU за всё время сообщил ---" | tee -a "${LOG}"
tail -10 "${QERR}" 2>/dev/null | tee -a "${LOG}"
kill "${QPID}" 2>/dev/null || true
date -u +"окончание: %Y-%m-%d %H:%M UTC" | tee -a "${LOG}"
exit 0
