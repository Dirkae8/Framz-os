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
rm -f "${SOCK}" "${SERIAL}"
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
      VARS_SRC="$(dirname "${OVMF_CODE}")/OVMF_VARS_4M.fd"; [ -f "${VARS_SRC}" ] || VARS_SRC="$(dirname "${OVMF_CODE}")/OVMF_VARS.fd"
      cp "${VARS_SRC}" /tmp/framz-OVMF_VARS.fd
      FW_ARGS=(-drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" -drive "if=pflash,format=raw,file=/tmp/framz-OVMF_VARS.fd")
      ;;
  esac
  echo "UEFI: ${OVMF_CODE}" | tee -a "${LOG}"
else
  echo "BIOS: SeaBIOS (по умолчанию)" | tee -a "${LOG}"
fi

qemu-system-x86_64 \
  -machine q35 -m 4096 -smp 4 -accel tcg \
  "${FW_ARGS[@]}" \
  -drive "file=${ISO},media=cdrom,readonly=on" \
  -boot d -display none -vnc none \
  -monitor "unix:${SOCK},server,nowait" \
  -serial "file:${SERIAL}" \
  >/dev/null 2>&1 &
QPID=$!
echo "QEMU запущен (pid ${QPID})" | tee -a "${LOG}"

shot() { # $1 = номер снимка
  local n="$1" ppm="/tmp/boot-${FIRMWARE}-${n}.ppm" state
  state="$(python3 scripts/iso-qemu-shot.py "${SOCK}" "${n}" "${ppm}" 2>&1 | tr -d '\r' | grep -v '^(qemu)' | grep 'VM status' | head -1)"
  if [ -f "${ppm}" ]; then
    convert "${ppm}" "${OUTDIR}/iso-boot-${TAG}-${FIRMWARE}-${n}.png" 2>/dev/null \
      && echo "снимок ${n}: ${state:-состояние неизвестно} → iso-boot-${TAG}-${FIRMWARE}-${n}.png" | tee -a "${LOG}" \
      || { cp "${ppm}" "${OUTDIR}/iso-boot-${TAG}-${FIRMWARE}-${n}.ppm"; echo "снимок ${n}: без конвертера, оставлен ppm" | tee -a "${LOG}"; }
  else
    echo "снимок ${n}: не получился" | tee -a "${LOG}"
  fi
}

for i in $(seq 1 "${SHOTS}"); do
  sleep 300
  shot "${i}"
done

echo | tee -a "${LOG}"
echo "--- последние строки последовательного порта ---" | tee -a "${LOG}"
if [ -s "${SERIAL}" ]; then tail -20 "${SERIAL}" | tee -a "${LOG}"; else echo "(пусто — установщик графический)" | tee -a "${LOG}"; fi
kill "${QPID}" 2>/dev/null || true
date -u +"окончание: %Y-%m-%d %H:%M UTC" | tee -a "${LOG}"
exit 0
