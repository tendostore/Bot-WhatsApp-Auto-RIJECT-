<div align="center">

# 📵 WhatsApp Bot Auto-Reject

**Bot penolak panggilan WhatsApp otomatis untuk toko digital & layanan berbasis chat**

[![Node.js](https://img.shields.io/badge/Node.js-22%20LTS-339933?logo=node.js&logoColor=white)](https://nodejs.org)
[![Baileys](https://img.shields.io/badge/Baileys-6.7.23-25D366?logo=whatsapp&logoColor=white)](https://github.com/WhiskeySockets/Baileys)
[![PM2](https://img.shields.io/badge/Process%20Manager-PM2-2B037A?logo=pm2&logoColor=white)](https://pm2.keymetrics.io)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](#lisensi)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Termux-lightgrey?logo=linux)](#kebutuhan-sistem)

[Instalasi](#-instalasi) •
[Konfigurasi](#-konfigurasi) •
[Manajemen](#-manajemen-bot-pm2) •
[Troubleshooting](#-troubleshooting)

</div>

---

## 📖 Tentang

**WhatsApp Bot Auto-Reject** adalah script installer satu-perintah yang men-deploy bot WhatsApp untuk **menolak seluruh panggilan masuk** (voice & video call) secara otomatis dan membalasnya dengan pesan teks yang mengarahkan penelepon untuk chat. Dibangun di atas [Baileys](https://github.com/WhiskeySockets/Baileys) dan dijalankan permanen dengan PM2 — cocok untuk toko PPOB, jasa konfigurasi, atau bisnis apa pun berbasis WhatsApp yang ingin meminimalkan gangguan telepon dan mengarahkan semua transaksi ke chat.

## ✨ Fitur

| Fitur | Keterangan |
|---|---|
| 🚫 **Auto-reject call** | Semua panggilan suara/video masuk otomatis ditolak dalam hitungan detik |
| 💬 **Balasan otomatis** | Penelepon menerima pesan yang mengarahkan mereka untuk chat |
| 🧊 **Anti-spam cooldown** | Maksimal satu balasan per nomor setiap 5 menit, mencegah flood pesan |
| 👤 **Whitelist admin** | Nomor tertentu bisa dikecualikan dari auto-reject via `ADMIN_NUMBERS` |
| 🔐 **Pairing via kode** | Login tanpa scan QR — cukup masukkan kode ke HP |
| 🔄 **Auto-reconnect** | Reconnect otomatis dengan backoff bertahap saat koneksi putus |
| 🧹 **Auto-recovery sesi** | Sesi kedaluwarsa/logout dibersihkan otomatis, bot berhenti rapi (bukan restart loop) |
| 🛡️ **Proteksi kredensial** | Folder sesi WhatsApp otomatis di-restrict permission (700/600) |
| ⚙️ **24/7 via PM2** | Auto-restart dan auto-start setelah reboot VPS |

## 🧱 Arsitektur Singkat

```
install.sh          → Installer: setup Node.js, PM2, generate project, pairing, deploy
└── wa-bot-anticall/
    ├── index.js             → Logika bot (Baileys)
    ├── package.json
    ├── node_modules/
    └── auth_info_baileys/   → Kredensial sesi WhatsApp (JANGAN commit ke git)
```

## 🔧 Kebutuhan Sistem

- Linux VPS (Ubuntu/Debian direkomendasikan) atau Termux di Android
- Akses `root`/`sudo` (untuk instalasi paket sistem & auto-start service)
- Node.js 22 LTS — dipasang otomatis oleh installer bila belum ada
- Koneksi internet stabil

## 🚀 Instalasi

```bash
git clone https://github.com/tendostore/Bot-WhatsApp-Auto-RIJECT-.git
cd Bot-WhatsApp-Auto-RIJECT-
chmod +x install.sh
./install.sh
```

Installer akan otomatis:

1. Memasang/memperbarui **Node.js 22 LTS** dan **PM2**.
2. Membuat folder proyek `wa-bot-anticall/` beserta `package.json` dan `index.js`.
3. Memasang dependency (`@whiskeysockets/baileys`, `pino`).
4. Memvalidasi syntax `index.js` sebelum dijalankan.
5. Menjalankan proses **pairing** — masukkan nomor WhatsApp, lalu masukkan kode yang muncul ke **Perangkat Tertaut** di aplikasi WhatsApp.
6. Mendaftarkan bot ke **PM2**, termasuk konfigurasi auto-start saat VPS reboot.

## ⚙️ Konfigurasi

### Whitelist nomor admin

Nomor yang didaftarkan tidak akan diblokir/dibalas otomatis saat menelepon:

```bash
export ADMIN_NUMBERS="628123456789,628987654321"
./install.sh
```

> Format: kode negara tanpa `+`, dipisah koma, tanpa spasi.

### Variabel lingkungan

| Variabel | Wajib | Default | Deskripsi |
|---|---|---|---|
| `ADMIN_NUMBERS` | Tidak | *(kosong)* | Daftar nomor yang dikecualikan dari auto-reject |
| `SETUP_MODE` | Otomatis | `true` saat pairing | Mengaktifkan mode pairing interaktif |

## 🕹️ Manajemen Bot (PM2)

| Perintah | Fungsi |
|---|---|
| `pm2 status bot-wa` | Cek status bot |
| `pm2 logs bot-wa` | Lihat log realtime |
| `pm2 restart bot-wa` | Restart bot |
| `pm2 stop bot-wa` | Hentikan bot |
| `pm2 delete bot-wa` | Hapus bot dari PM2 |

## 🔁 Re-pairing / Login Ulang

Jika sesi logout (misalnya perangkat di-unlink dari HP), sesi lama otomatis dihapus dan bot berhenti sendiri. Untuk pairing ulang:

```bash
cd wa-bot-anticall
SETUP_MODE=true node index.js
```

Setelah berhasil terhubung:

```bash
pm2 restart bot-wa
```

## 🛠️ Troubleshooting

| Masalah | Solusi |
|---|---|
| Kode pairing gagal terus | Pastikan nomor WA aktif dan tidak login di terlalu banyak perangkat lain |
| Bot tidak auto-start setelah reboot | Jalankan `pm2 startup` manual, ikuti instruksi `sudo`, lalu `pm2 save` |
| Panggilan tidak ditolak | Cek `pm2 logs bot-wa`, pastikan status `online` & WhatsApp `connected` |
| Nomor admin masih diblokir | Pastikan format `ADMIN_NUMBERS` benar dan bot sudah di-restart setelah env diubah |

## 🔒 Keamanan

- Folder `auth_info_baileys/` berisi kredensial sesi WhatsApp aktif — **jangan pernah** commit ke repository. Tambahkan ke `.gitignore`.
- Folder tersebut otomatis dibatasi permission-nya (`700` untuk direktori, `600` untuk file) setiap kali kredensial diperbarui.
- Jangan bagikan isi folder ini ke pihak mana pun; siapa saja yang memilikinya bisa mengambil alih sesi WhatsApp Anda.

## ⚠️ Disclaimer

Proyek ini menggunakan [Baileys](https://github.com/WhiskeySockets/Baileys), library tidak resmi untuk WhatsApp Web. Gunakan sesuai [Ketentuan Layanan WhatsApp](https://www.whatsapp.com/legal/terms-of-service). Risiko pembatasan/pemblokiran nomor sepenuhnya menjadi tanggung jawab pengguna.

## 🤝 Kontribusi

Pull request dan issue sangat diterima. Untuk perubahan besar, buka issue terlebih dahulu untuk mendiskusikan apa yang ingin diubah.

## 📄 Lisensi

Didistribusikan di bawah lisensi [MIT](LICENSE).

---

<div align="center">
Dibuat dengan ❤️ oleh <a href="https://github.com/tendostore">tendostore</a>
</div>
