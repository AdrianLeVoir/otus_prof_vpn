# Домашнее задание: VPN

## Текст задания

1. Настроить VPN между двумя ВМ в tun/tap режимах, замерить скорость в туннелях, сделать вывод об отличающихся показателях.
2. Поднять RAS на базе OpenVPN с клиентскими сертификатами, подключиться с локальной машины на ВМ.
3. (*) Самостоятельно изучить и настроить ocserv, подключиться с хоста к ВМ.

Реализация на Proxmox-стенде, формат — ansible.

## Схема сети

```
Локальная машина (192.168.1.236)
   │
   ├── TCP/UDP 8443 ──> vpnserver (192.168.1.153)   [RAS OpenVPN :1207/udp, ocserv :8443]
   │                          │
   │                     direct-link 10.0.0.0/30
   │                          │
   │                     vpnclient (192.168.1.154, 10.0.0.2)
   │
   └── RAS-туннель: tun 10.10.10.6 <──> 10.10.10.1 (vpnserver)
```

- ВМ: vpnserver (523), vpnclient (524), Ubuntu 24.04, прямой линк 10.0.0.0/30.
- vpnserver: OpenVPN (static-key tunnel + RAS), easy-rsa PKI, ocserv.
- vpnclient: OpenVPN-клиент static-key, iperf3.

## 1. Туннели tun/tap и замер скорости

OpenVPN со статическим ключом (P2P):

```
dev tun | tap
local 10.0.0.1 | 10.0.0.2
remote 10.0.0.2 | 10.0.0.1
ifconfig 10.10.10.1 10.10.10.2        (tun)
ifconfig 10.10.10.1 255.255.255.0     (tap)
secret /etc/openvpn/static.key
cipher AES-256-CBC
```

Замер iperf3 (vpnclient → vpnserver через туннель, -t 10):

| Режим | Скорость (receiver) |
|---|---|
| tun | ~293–294 Mbit/s |
| tap | ~278 Mbit/s |

**Вывод**: tun быстрее tap (~5%). Причины:
- tun работает на L3 (IP-пакеты) — передаётся только полезная нагрузка;
- tap работает на L2 (Ethernet-кадры) — в туннель инкапсулируются кадры целиком,
  включая заголовки Ethernet (14 байт/пакет), что даёт дополнительную накладные
  расходы на инкапсуляцию; для iperf3 TCP это заметно на коротких замерах.
- Дополнительно в tap-режиме нет автоматической фильтрации broadcast-трафика.

Особенности: OpenVPN 2.6 в static-key режиме не принимает GCM-шифры
(`Cipher 'AES-256-GCM' mode not supported`) — нужен CBC (AES-256-CBC).

## 2. RAS на базе OpenVPN с клиентскими сертификатами

На vpnserver установлены `openvpn` + `easy-rsa`, создан PKI:

```
easyrsa init-pki
easyrsa build-ca nopass
easyrsa gen-req server nopass && easyrsa sign-req server server
easyrsa gen-req client nopass && easyrsa sign-req client client
easyrsa gen-dh
```

Серверный конфиг (`/etc/openvpn/server.conf`):
`port 1207, proto udp, dev tun, ca/cert/key/dh из pki, server 10.10.10.0 255.255.255.0, client-to-client, keepalive 10 120`.

Проверка с локальной машины:

```
$ sudo openconnect ... # нет, это для ocserv; для RAS:
$ sudo openvpn --config client.conf
Initialization Sequence Completed
tun0: inet 10.10.10.6 peer 10.10.10.5/32

$ ping -c 4 10.10.10.1
3 packets transmitted, 3 received, 0% packet loss
```

Маршрут 10.10.10.0/24 импортирован в таблицу маршрутизации хоста.
Файлы клиента (client.conf, ca.crt, client.crt, client.key) — в `client/`.

## 3. (*) OpenConnect-сервер (ocserv)

На vpnserver установлен `ocserv` (порт 8443 tcp+udp):

```
listen-host = 0.0.0.0
tcp-port = 8443
udp-port = 8443
server-cert = /etc/openvpn/pki/issued/server.crt   (тот же PKI)
server-key  = /etc/openvpn/pki/private/server.key
ca-cert = /etc/openvpn/pki/ca.crt
auth = "plain[passwd=/etc/ocserv/ocpasswd]"
device = vpns
ipv4-network = 10.11.11.0/24
ipv4-netmask = 255.255.255.0
socket-file = /run/ocserv.socket
```

Пользователь создан через `ocpasswd`. Подключение с хоста:

```
$ sudo openconnect --servercert pin-sha256:... -u testuser \
    -Q 8 --script /tmp/mini-vpnc.sh \
    --background https://192.168.1.153:8443
Настроено как 10.11.11.121, с SSL подключено и DTLS подключено

$ ping -c 4 10.11.11.1
4 packets transmitted, 4 received, 0% packet loss
```

## Файлы

| Файл | Назначение |
|---|---|
| `openvpn/static-server.conf` | static-key туннель (сервер, tun-режим) |
| `openvpn/static-client.conf` | static-key туннель (клиент) |
| `openvpn/ras-server.conf` | RAS-сервер с PKI |
| `client/client.conf` | клиент RAS для хоста |
| `client/mini-vpnc.sh` | минимальный vpnc-script для openconnect |
| `ocserv/ocserv.conf` | конфигурация OpenConnect-сервера |
| `README.md` | этот файл |
