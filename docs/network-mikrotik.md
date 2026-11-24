# คู่มือเครือข่าย: MikroTik hAP ac² เป็น Wi-Fi client ปล่อย LAN ให้ชั้นบน

ใช้เมื่อ AI Server และ NAS อยู่คนละชั้นกับ router ของ ISP และ**ไม่มีสาย LAN เดินระหว่างชั้น** ให้ MikroTik hAP ac² รับเน็ตผ่าน Wi-Fi จาก router ชั้นล่าง แล้วปล่อยเป็นสาย LAN และ Wi-Fi ให้ชั้นบน

> คู่มือนี้ทดสอบจริงกับ hAP ac² (RouterOS 6.48 → 6.49) และ router ของ True (Skyworth GN542VF) · ชื่อ Wi-Fi และรหัสผ่านในคู่มือเป็นตัวอย่าง ให้แทนด้วยของจริง

## ภาพรวม

```
ชั้นล่าง (192.168.1.x)                        ชั้นบน (192.168.88.x)
[Router ISP 192.168.1.1] ~~~ Wi-Fi 2.4GHz ~~~► wlan1 [hAP ac²: Wi-Fi client + router]
                                               IP ตายตัว 192.168.1.30
                                                  ├── ether2 ── AI Server   192.168.88.20
                                                  ├── ether3 ── NAS         192.168.88.10
                                                  ├── ether1,4,5 ── เครื่องอื่น
                                                  └── wlan2 (5GHz) ── Wi-Fi ชั้นบน
```

### ทำไมเป็นโหมด router ไม่ใช่ bridge

hAP ที่เป็น Wi-Fi client ของ router ยี่ห้ออื่น**ทำ bridge ให้หลายเครื่องไม่ได้อย่างเสถียร** (มาตรฐาน Wi-Fi ปกติไม่รองรับ) จึงให้ hAP เป็น router ของชั้นบน

| เรื่อง | ผล |
|---|---|
| Server ↔ NAS | ✅ เร็วเต็ม gigabit (วิ่งผ่าน switch ใน hAP ไม่ผ่าน Wi-Fi) |
| อินเทอร์เน็ตชั้นบน | ขึ้นกับสัญญาณ Wi-Fi ระหว่างชั้น (2.4GHz ราว 50–140 Mbps) |
| เครื่องชั้นล่างเข้า server/NAS | ผ่าน port forward ที่ IP `192.168.1.30` |
| Tailscale | ✅ ใช้ได้ปกติ |
| ถ้า Wi-Fi ระหว่างชั้นหลุด | ชั้นบนไม่มีเน็ต แต่ server กับ NAS ยังคุยกันได้ และ backup ยังทำงาน |

### ทำไมรับเน็ตด้วย 2.4GHz

ทะลุพื้นและผนังได้ดีกว่า และทำให้ Wi-Fi ชั้นบนได้ใช้ 5GHz ที่เร็วกว่า ถ้าสัญญาณ 5GHz จากชั้นล่างถึงชั้นบนได้ดีกว่า -70 dBm จะสลับไปรับด้วย 5GHz ก็ได้ (เร็วกว่า แต่ Wi-Fi ชั้นบนจะเหลือ 2.4GHz)

---

## สิ่งที่ต้องเตรียม

- **WinBox 4** สำหรับ Mac หรือ Windows (ดาวน์โหลดจาก mikrotik.com)
- **สาย LAN** ต่อ MacBook เข้า ether2 ของ hAP ระหว่างตั้งค่า (ถ้าไม่มีช่อง LAN ใช้ USB-C to Ethernet)
- ชื่อและรหัส **Wi-Fi 2.4GHz ของ router ชั้นล่าง**
- วาง hAP **ในจุดที่รับสัญญาณจากชั้นล่างได้ดี** เช่นใกล้บันได

## เคล็ดลับการใช้ Terminal ของ WinBox

- **อย่าเปิด Safe Mode** ระหว่างตั้งค่าตามคู่มือนี้ เพราะตอนเปลี่ยนพอร์ตเข้า bridge การเชื่อมต่อของ WinBox จะสะดุดสั้นๆ Safe Mode จะเข้าใจว่าหลุด และยกเลิกการตั้งค่าทั้งหมด
- วางคำสั่งทีละก้อนตามคู่มือ ถ้ามี error ให้หยุดและอ่านข้อความก่อนทำต่อ
- ถ้าตั้งพลาด กู้คืนได้เสมอ (ดูหัวข้อ "กู้คืน" ท้ายคู่มือ)

---

## ขั้นที่ 1: ตรวจสัญญาณ

เข้า WinBox ทาง MAC address (แท็บ Neighbors) หรือ `192.168.88.1` แล้วเปิด **New Terminal**:

```
/interface wireless scan wlan1 duration=10
```

หาชื่อ Wi-Fi ชั้นล่างในคอลัมน์ SSID แล้วดูคอลัมน์ **SIG**:

| SIG | ผล |
|---|---|
| ดีกว่า -65 (เช่น -56) | ดี |
| -65 ถึง -75 | พอใช้ |
| แย่กว่า -75 | ย้าย hAP ไปใกล้ router ชั้นล่างขึ้น |

## ขั้นที่ 2: รีเซ็ตเป็นค่าเริ่มต้นของ MikroTik

ใช้ค่าเริ่มต้น (ไม่ใช่แบบ no-defaults) เพราะมี router, DHCP, NAT และ firewall ตั้งไว้ให้ครบ:

```
/system reset-configuration skip-backup=yes
```

กด `y` แล้วรอราว 1 นาที เข้า WinBox ใหม่ทาง MAC address (user `admin` รหัสผ่านว่าง หรือดูจากสติกเกอร์ใต้เครื่อง)

ถ้ามีหน้าต่าง **RouterOS Default Configuration** ขึ้นมา ให้กด **OK** (อย่ากด Remove Configuration)

## ขั้นที่ 3: ตั้งเป็น Wi-Fi client + router

แก้ค่าในเครื่องหมายคำพูด 4 จุด แล้ววางทั้งก้อน:

```
/interface wireless security-profiles add name=home-uplink mode=dynamic-keys authentication-types=wpa-psk,wpa2-psk unicast-ciphers=tkip,aes-ccm group-ciphers=tkip,aes-ccm wpa-pre-shared-key="รหัสWiFiชั้นล่าง" wpa2-pre-shared-key="รหัสWiFiชั้นล่าง"
/interface wireless security-profiles set default mode=dynamic-keys authentication-types=wpa2-psk wpa2-pre-shared-key="รหัสWiFiชั้นบน"
/interface bridge port remove [find interface=wlan1]
/interface wireless set wlan1 mode=station ssid="ชื่อWiFiชั้นล่าง" security-profile=home-uplink country=thailand disabled=no
/interface wireless set wlan2 mode=ap-bridge ssid="ชื่อWiFiชั้นบน" security-profile=default country=thailand disabled=no
/interface list member remove [find interface=ether1 list=WAN]
/interface list member add list=WAN interface=wlan1
/ip dhcp-client remove [find interface=ether1]
/ip dhcp-client add interface=wlan1 disabled=no comment="uplink via WiFi"
/system identity set name=upstairs-router
/system clock set time-zone-name=Asia/Bangkok
/system ntp client set enabled=yes primary-ntp=162.159.200.1 secondary-ntp=162.159.200.123
/interface bridge port add bridge=bridge interface=ether1
```

**สิ่งที่คำสั่งนี้ทำ:**
- **wlan1 (2.4GHz)** เกาะ Wi-Fi ชั้นล่าง และรับการเข้ารหัสได้ทั้ง AES และ TKIP (router ของ ISP หลายรุ่นยังใช้ TKIP ผสมอยู่ ถ้ารับแค่ AES จะค้างที่ `searching-for-network`)
- **wlan2 (5GHz)** ปล่อย Wi-Fi ชั้นบนพร้อมรหัสผ่าน (ค่าเริ่มต้นของ RouterOS v6 รุ่นเก่าเปิด Wi-Fi แบบไม่มีรหัส)
- **ether1–5** เป็นพอร์ต LAN ทั้งหมด
- NAT, firewall และ DHCP แจก `192.168.88.x` ใช้ค่าเริ่มต้นของ MikroTik ต่อได้เลย

**หมายเหตุ RouterOS v6:** คำสั่ง NTP แบบ `server-dns-names=` ใช้ไม่ได้ใน v6.48 จึงใช้ `primary-ntp=` กับ IP ของ Cloudflare แทน

## ขั้นที่ 4: ตรวจการเชื่อมต่อ

รอ 15 วินาที แล้วรันทีละคำสั่ง:

```
/interface wireless monitor wlan1 once
```

```
/ip dhcp-client print
```

```
/ping 8.8.8.8 count=4
```

| ต้องเห็น | ถ้าไม่เห็น |
|---|---|
| `status: connected-to-ess` และ signal ดีกว่า -70 dBm | ดูหัวข้อ "แก้ปัญหา" |
| DHCP client สถานะ `bound` ได้ IP `192.168.1.x` | — |
| ping ได้ครบ 4 ครั้ง | — |

## ขั้นที่ 5: อัปเดต RouterOS และตั้งรหัส admin

สำรองค่าก่อน:

```
/export file=before-upgrade
```

อัปเดต RouterOS (เครื่องจะรีบูตเอง ใช้เวลา 2–5 นาที **ห้ามถอดปลั๊ก**):

```
/system package update check-for-updates
```

```
/system package update install
```

หลังเชื่อมต่อกลับมาได้ อัปเดต firmware ของบอร์ด (ถ้า `current-firmware` ต่างจาก `upgrade-firmware`):

```
/system routerboard print
```

```
/system routerboard upgrade
```

```
/system reboot
```

ตั้งรหัส admin (ตอนแรกว่างอยู่ กด Enter ที่รหัสเก่าได้เลย):

```
/password
```

**ควรอยู่ที่ v6 ต่อไป:** hAP ac² มีพื้นที่เก็บข้อมูลแค่ 16MB และทุกคำสั่งในคู่มือนี้เขียนสำหรับ v6

## ขั้นที่ 6: ตั้ง IP ตายตัวฝั่งชั้นล่าง

IP ของ hAP ฝั่งชั้นล่างต้องไม่เปลี่ยน เพราะเครื่องชั้นล่างใช้ IP นี้เข้าถึง server และ NAS

**6.1 หาช่วง IP ที่ router ชั้นล่างไม่ได้แจก:** เข้าหน้า admin ของ router (ปกติ `http://192.168.1.1`) ดูที่หน้า LAN/DHCP ว่า DHCP แจกช่วงไหน เช่น `192.168.1.33` ถึง `.254` แปลว่า `.2` ถึง `.32` เป็นช่วงว่าง

**6.2 ตรวจว่า IP ที่จะใช้ว่างจริง** (ต้องได้ timeout ทั้ง 3 ครั้ง):

```
/ping 192.168.1.30 count=3
```

**6.3 ตั้ง IP ตายตัว:**

```
/ip dhcp-client remove [find interface=wlan1]
/ip address add address=192.168.1.30/24 interface=wlan1 comment="static uplink"
/ip route add gateway=192.168.1.1
/ip dns set servers=192.168.1.1,1.1.1.1
```

ตรวจ:

```
/ping 8.8.8.8 count=4
```

```
/ping google.com count=2
```

**ทำไมไม่จอง IP บน router ของ ISP:** router ของ ISP มักไม่มีเมนูจอง IP ในบัญชีผู้ใช้ทั่วไป และ ISP อาจรีเซ็ตค่า router จากระยะไกล ค่าที่ตั้งบน hAP ของเราเองจึงทนกว่า

## ขั้นที่ 7: Port forward ให้ชั้นล่างเข้าถึง server และ NAS

```
/ip firewall nat
add chain=dstnat in-interface-list=WAN protocol=tcp dst-port=3000 action=dst-nat to-addresses=192.168.88.20 comment="Open WebUI"
add chain=dstnat in-interface-list=WAN protocol=tcp dst-port=5001 action=dst-nat to-addresses=192.168.88.10 comment="NAS DSM"
add chain=dstnat in-interface-list=WAN protocol=tcp dst-port=445 action=dst-nat to-addresses=192.168.88.10 comment="NAS SMB"
```

ตรวจว่าบันทึกครบ 3 รายการ:

```
/ip firewall nat print where action=dst-nat
```

พอร์ตเหล่านี้เปิดให้**เฉพาะเครื่องในบ้าน**เท่านั้น ไม่ได้เปิดออกอินเทอร์เน็ต เพราะ router ของ ISP ไม่ได้ forward ออกไป ส่วน Remote Desktop และหน้าตั้งค่า hAP ไม่ได้เปิดให้ชั้นล่าง ให้จัดการจากชั้นบนหรือผ่าน Tailscale

## ขั้นที่ 8: ต่อ NAS และจอง IP

1. ใน DSM ตั้ง LAN เป็น **Get network configuration automatically (DHCP)** (ถ้าเคยตั้ง IP ตายตัวไว้ ดูหัวข้อถัดไป)
2. เสียบ NAS ที่ **ether3** รอ 1 นาที แล้วดูรายการ:

```
/ip dhcp-server lease print
```

3. จองด้วย MAC address ของ NAS (แทน `XX:XX:XX:XX:XX:XX` ด้วยค่าจริง):

```
/ip dhcp-server lease make-static [find mac-address=XX:XX:XX:XX:XX:XX]
```

```
/ip dhcp-server lease set [find mac-address=XX:XX:XX:XX:XX:XX] address=192.168.88.10 comment="NAS"
```

4. รีสตาร์ต NAS แล้วรอ 3–5 นาที จากนั้นตรวจ:

```
/ping 192.168.88.10 count=3
```

ทำแบบเดียวกันกับ **AI Server** ที่ **ether2** โดยจองเป็น `192.168.88.20` หลังติดตั้ง Windows (หรือ Ubuntu) เสร็จ

### กรณี NAS เคยตั้ง IP ตายตัวไว้คนละวง

ตัวอย่าง: NAS ตั้งไว้ที่ `192.168.30.200` ทำให้เข้า DSM จากวง `192.168.88.x` ไม่ได้ ให้เปิดทางชั่วคราว:

```
/ip address add address=192.168.30.1/24 interface=bridge comment="TEMP old NAS network"
/ip firewall nat add chain=srcnat dst-address=192.168.30.0/24 action=masquerade comment="TEMP old NAS network"
```

คำสั่งที่สองจำเป็น เพราะ NAS จะส่งคำตอบไปที่ gateway เก่าที่ไม่มีอยู่แล้ว การ masquerade ทำให้ NAS เห็นคำขอเป็น IP วงเดียวกัน

จากนั้นเข้า `https://192.168.30.200:5001` แล้วเปลี่ยน LAN เป็น DHCP ทำขั้นที่ 8 ต่อ และ**ลบของชั่วคราวเมื่อเสร็จ**:

```
/ip firewall nat remove [find comment="TEMP old NAS network"]
/ip address remove [find comment="TEMP old NAS network"]
```

## ขั้นที่ 9: ทดสอบและสำรองค่า

| จาก | เปิด | ต้องเห็น |
|---|---|---|
| ชั้นบน | `https://192.168.88.10:5001` | หน้า DSM |
| ชั้นล่าง (Wi-Fi ของ ISP) | `https://192.168.1.30:5001` | หน้า DSM |

ทดสอบชั้นล่างด้วย**โน้ตบุ๊ก**จะชัดเจนที่สุด (มือถือมักมีปัญหาเฉพาะตัว ดูหัวข้อแก้ปัญหา)

สำรองค่าที่ตั้งไว้ทั้งหมด:

```
/export file=hap-final
```

แล้วไปที่เมนู **Files** ใน WinBox ลากไฟล์ `hap-final.rsc` มาเก็บไว้ ไฟล์นี้มีรหัส Wi-Fi อยู่ข้างใน **อย่า commit ขึ้น GitHub**

---

## ที่อยู่สำหรับใช้งาน

| บริการ | จากชั้นล่าง | จากชั้นบน |
|---|---|---|
| แชท AI (Open WebUI) | `http://192.168.1.30:3000` | `http://192.168.88.20:3000` |
| หน้าจัดการ NAS (DSM) | `https://192.168.1.30:5001` | `https://192.168.88.10:5001` |
| ไฟล์ NAS (Finder: ⌘K) | `smb://192.168.1.30` | `smb://192.168.88.10` |
| ตั้งค่า hAP (WinBox) | ❌ เข้าไม่ได้ (ตั้งใจให้ปลอดภัย) | `192.168.88.1` |
| Remote Desktop เข้า server | ❌ (ใช้ Tailscale แทน) | `192.168.88.20` |

**ค่าสำหรับคู่มือติดตั้ง ([install.md](install.md)):** server `192.168.88.20` และ `setup-backup.ps1` ใช้ IP ของ NAS `192.168.88.10`

---

## แก้ปัญหา

| อาการ | สาเหตุ | แก้ |
|---|---|---|
| วางคำสั่งแล้ว ชื่อเครื่องกลับเป็น `MikroTik` และการตั้งค่าหายหมด | **Safe Mode** ยกเลิกการเปลี่ยนแปลงเมื่อ WinBox สะดุด | ปิด Safe Mode แล้ววางคำสั่งใหม่ |
| `monitor wlan1` ค้างที่ `searching-for-network` แต่ `scan` เห็น Wi-Fi ชั้นล่าง | การเข้ารหัสไม่ตรง (router ใช้ TKIP ผสม) | ใช้ security profile ตามขั้นที่ 3 ที่รับทั้ง TKIP และ AES |
| `scan` ไม่เห็น Wi-Fi ชั้นล่าง | สัญญาณไม่ถึง หรือ router ซ่อนชื่อ Wi-Fi | ย้าย hAP ให้ใกล้ขึ้น |
| เชื่อมต่อไม่ได้ และ log มี `unicast key exchange timeout` | รหัสผิด หรือ router ตั้งเป็น **WPA3 อย่างเดียว** (RouterOS v6 ไม่รองรับ WPA3) | ตรวจรหัส และตั้ง router ชั้นล่างเป็น WPA2 หรือ WPA2/WPA3 แบบผสม |
| ping NAS จาก hAP ได้ แต่ Mac เปิดหน้า DSM ไม่ได้ (NAS อยู่คนละวง) | NAS ส่งคำตอบไปที่ gateway เก่า | เพิ่ม masquerade ชั่วคราวตามหัวข้อ "NAS เคยตั้ง IP ตายตัวไว้คนละวง" |
| ชั้นล่างเข้า `192.168.1.30` ไม่ได้ | ดูขั้นตอนตรวจด้านล่าง | — |
| หลังสั่งอัปเดต WinBox เข้าไม่ได้ | กำลังติดตั้ง | รอ 2–5 นาที ถอดเสียบสาย LAN ของ Mac แล้วลองเข้าทาง MAC address ใหม่ |

### ตรวจเมื่อชั้นล่างเข้าไม่ได้

**1. ดูว่าการเชื่อมต่อมาถึง hAP หรือไม่:** ให้เครื่องชั้นล่างเปิด `https://192.168.1.30:5001` แล้วรันทันที:

```
/ip firewall nat print stats where action=dst-nat
```

**2. ถ้า PACKETS เป็น 0:** ตรวจว่า hAP มองเห็นอุปกรณ์ชั้นล่างหรือไม่ (กด `Q` เพื่อหยุด):

```
/tool ip-scan interface=wlan1 address-range=192.168.1.0/24 duration=30
```

| ผล | สาเหตุ | แก้ |
|---|---|---|
| เห็นแค่ `192.168.1.1` | router ของ ISP เปิด **AP Isolation** | ปิดในเมนู WLAN ของ router หรือให้เครื่องชั้นล่างต่อด้วยสาย LAN หรือใช้ Tailscale |
| เห็นหลายเครื่อง แต่ PACKETS ยังเป็น 0 | ปัญหาอยู่ที่**อุปกรณ์ที่ใช้ทดสอบ** | ดูด้านล่าง |

**ปัญหาเฉพาะของอุปกรณ์:**
- **iPhone:** ใช้ Safari หรือเปิดสิทธิ์ที่ **การตั้งค่า > ความเป็นส่วนตัวและความปลอดภัย > เครือข่ายเฉพาะที่** ให้เบราว์เซอร์ที่ใช้
- **Android (เช่น Samsung):** ปิดข้อมูลมือถือ, ปิด VPN และ **Wi-Fi ที่ปลอดภัย (Secure Wi-Fi)** และปิดการสลับไปใช้ข้อมูลมือถืออัตโนมัติใน Intelligent Wi-Fi
- ใช้ IP ที่ถูกต้องของอุปกรณ์เวลาทดสอบ ping (ดูในการตั้งค่า Wi-Fi ของอุปกรณ์)

**3. ถ้า PACKETS มากกว่า 0 แต่ยังเปิดไม่ได้:** firewall ของปลายทาง (เช่น DSM) อาจอนุญาตเฉพาะบางวง IP ให้ hAP แปลงที่อยู่ให้:

```
/ip firewall nat add chain=srcnat src-address=192.168.1.0/24 dst-address=192.168.88.0/24 action=masquerade comment="downstairs via port forward"
```

---

## กู้คืน

**ตั้งพลาดจนเข้าไม่ได้:** ถอดปลั๊ก กดปุ่ม **Reset** ค้างไว้ แล้วเสียบปลั๊กกลับ รอจนไฟ USR กะพริบแล้วปล่อย เครื่องจะกลับเป็นค่าเริ่มต้น จากนั้นเริ่มใหม่ที่ขั้นที่ 3

**กู้จากไฟล์สำรอง:** ลากไฟล์ `hap-final.rsc` เข้าเมนู Files แล้วรัน:

```
/import file-name=hap-final.rsc
```

(ควรรันหลังรีเซ็ตแบบ no-defaults เพื่อไม่ให้ค่าซ้ำซ้อนกับค่าเริ่มต้น)

## ความปลอดภัย

- **ตั้งรหัส admin** ของ hAP ทันที (ขั้นที่ 5)
- ใช้รหัส Wi-Fi ยาว 12 ตัวขึ้นไปทั้งชั้นล่างและชั้นบน เพราะ server และ NAS อยู่ในเครือข่ายเดียวกันนี้
- ถ้าเข้าหน้า admin ของ router ชั้นล่างได้ ให้เปลี่ยนการเข้ารหัส Wi-Fi เป็น **WPA2-AES** อย่างเดียว (เลิกใช้ TKIP) hAP ยังเชื่อมต่อได้ตามปกติ
- **เปลี่ยนรหัส admin ของ router ISP** ถ้ายังใช้ค่าบนสติกเกอร์ใต้เครื่อง
- firewall ค่าเริ่มต้นของ MikroTik กั้นไม่ให้ชั้นล่างเข้าหน้าตั้งค่า hAP และเปิดให้เฉพาะพอร์ตที่ forward ไว้เท่านั้น

## ทางเลือกในอนาคต

ถ้าเดินสาย LAN ระหว่างชั้นได้ ให้เปลี่ยน hAP เป็นโหมด **bridge** (เป็น switch ธรรมดา) ทุกเครื่องในบ้านจะอยู่วงเดียวกัน ไม่ต้องใช้ port forward และเสถียรกว่า Wi-Fi ระหว่างชั้น
