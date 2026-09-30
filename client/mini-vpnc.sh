#!/bin/sh
# Минимальный vpnc-совместимый скрипт: поднимает tun и адрес из переменных openconnect
case "$reason" in
connect)
  ip link set "$TUNDEV" up
  ip addr add "$INTERNAL_IP4_ADDRESS"/32 dev "$TUNDEV" 2>/dev/null
  ip route add 10.11.11.0/24 dev "$TUNDEV" 2>/dev/null
  ;;
disconnect)
  ip link del "$TUNDEV" 2>/dev/null
  ;;
esac
exit 0