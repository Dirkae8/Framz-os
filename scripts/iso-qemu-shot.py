#!/usr/bin/env python3
"""FRAMZ OS — снимок экрана из виртуальной машины QEMU.

Подключается к монитору QEMU (unix-сокет), запрашивает состояние машины
и делает снимок экрана в PPM. Вынесено отдельным файлом, чтобы в workflow
не было многострочных вставок кода (они ломают YAML).

Использование:
    python3 scripts/iso-qemu-shot.py /tmp/qemu-monitor.sock 1 [путь.ppm]
"""
import socket
import sys
import time


def send(sock_path: str, command: str, wait: float = 3.0) -> str:
    """Отправить команду в монитор QEMU и вернуть ответ."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(60)
    try:
        s.connect(sock_path)
        s.recv(4096)                      # приветствие монитора
        s.sendall((command + "\n").encode())
        time.sleep(wait)
        try:
            return s.recv(65536).decode(errors="replace").strip()
        except Exception as exc:          # noqa: BLE001
            return f"(нет ответа: {exc})"
    finally:
        s.close()


def main() -> int:
    if len(sys.argv) < 3:
        print("использование: iso-qemu-shot.py СОКЕТ НОМЕР [файл.ppm]")
        return 2

    sock_path = sys.argv[1]
    number = sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else f"/tmp/boot-{number}.ppm"

    print(f"--- снимок {number} ---")
    try:
        print(send(sock_path, "info status"))
        print(send(sock_path, f"screendump {out}", wait=5.0))
    except Exception as exc:              # noqa: BLE001
        print(f"монитор недоступен: {exc}")
        return 1

    import os
    if os.path.exists(out):
        print(f"снимок записан: {out} ({os.path.getsize(out)} байт)")
        return 0
    print("снимок не создан (машина могла ещё не дойти до графики)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
