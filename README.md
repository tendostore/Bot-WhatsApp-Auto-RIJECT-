# 🚀 WhatsApp Bot Anti-Call (Auto-Reject & Fast Response)

**Link Instalasi Cepat (One-Click):**

wget -qO install.sh https://raw.githubusercontent.com/tendostore/Bot-WhatsApp-Auto-RIJECT-/main/install.sh && bash install.sh

---

Script otomatisasi WhatsApp yang dirancang khusus untuk penjual **Config (HTTP Custom, V2Ray, dll)** dan **Paket Data/PPOB**. Bot ini berfungsi untuk menjaga konsentrasi admin dengan menolak semua panggilan secara otomatis dan memberikan pesan pengalihan ke chat agar transaksi tetap lancar.

## ✨ Fitur Utama
- **Auto-Reject Call:** Menolak panggilan suara & video secara instan.
- **Auto-Reply Message:** Mengirim pesan otomatis setelah menolak telepon (Opsi: Fast Response).
- **Anti-Spam System:** Menghindari blokir WhatsApp dengan memberikan penanda waktu unik pada setiap pesan.
- **24/7 Runtime:** Terintegrasi dengan PM2 agar bot tetap menyala meskipun terminal VPS ditutup.
- **Silent Notification:** Bot berjalan tanpa mengganggu bunyi notifikasi chat masuk di HP utama.

## 🛠️ Pesan Peringatan
Setiap kali ada yang menelpon, bot akan mengirimkan pesan:
> "⚠️ **PANGGILAN OTOMATIS DITOLAK**
> Halo! 🙏 Untuk mempercepat proses pengisian paket data dan pembuatan config, kami tidak menerima telepon. Silakan langsung ketik pesanan kamu di sini. Admin akan segera memprosesnya! 🚀"

## 🚀 Langkah Instalasi
1. Masuk ke terminal VPS kamu via SSH.
2. Jalankan perintah instalasi di atas.
3. Masukkan nomor WhatsApp kamu (format: 62812xxx).
4. Masukkan **Kode Pairing** yang muncul di terminal ke aplikasi WhatsApp di HP kamu (Perangkat Tertaut > Tautkan Perangkat > Tautkan dengan nomor telepon saja).
5. Selesai! Bot akan otomatis berjalan di background menggunakan PM2.

## ⚙️ Perintah Manajemen (PM2)
- **Cek Status Bot:** pm2 status bot-wa
- **Melihat Log Transaksi:** pm2 logs bot-wa
- **Restart Bot:** pm2 restart bot-wa
- **Mematikan Bot:** pm2 stop bot-wa

---
**Dibuat dengan ❤️ untuk komunitas Pejuang Config & PPOB.**
