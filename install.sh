#!/bin/bash

# ==============================================================================
# Skrip Install Bot WhatsApp Auto Reject (Pairing Code)
# Didesain khusus untuk VPS, Auto-Yes, Auto-Reboot (PM2), dan menjaga Notif HP
# ==============================================================================

# 1. Pastikan tidak ada prompt / popup saat instalasi (Auto Yes mode)
export DEBIAN_FRONTEND=noninteractive

# Bersihkan layar sebelum mulai
clear
echo "=========================================================="
echo "       SETUP BOT WHATSAPP AUTO REJECT (CALL/VC)           "
echo "=========================================================="

# Meminta nomor WA sebelum instalasi otomatis berjalan
read -p "Masukkan Nomor WhatsApp (awali dengan kode negara, misal 628123456789): " WA_NUMBER

echo "=========================================================="
echo "Memulai Proses Instalasi. Duduk manis, semua berjalan otomatis..."
echo "=========================================================="

# 2. Update & Upgrade Sistem
sudo apt-get update -y
sudo apt-get upgrade -y

# 3. Instal dependensi dasar
sudo apt-get install -y curl git build-essential tzdata

# 4. Instal Node.js (Gunakan versi LTS 20)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# 5. Instal PM2 secara global untuk proses background & auto-reboot
sudo npm install -g pm2

# 6. Membuat direktori kerja bot
BOT_DIR="$HOME/bot-autoreject"
mkdir -p $BOT_DIR
cd $BOT_DIR

# 7. Simpan nomor WA ke file teks agar bisa dibaca oleh bot
echo "$WA_NUMBER" > wanumber.txt

# 8. Inisialisasi Project dan Instal dependensi bot (Baileys)
npm init -y
npm install @whiskeysockets/baileys pino

# 9. Membuat file utama bot (index.js)
cat << 'EOF' > index.js
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason, Browsers } = require('@whiskeysockets/baileys');
const pino = require('pino');
const fs = require('fs');

async function startBot() {
    // Menyimpan sesi login di folder auth_info_baileys
    const { state, saveCreds } = await useMultiFileAuthState('auth_info_baileys');

    const sock = makeWASocket({
        logger: pino({ level: 'silent' }), // Matikan log bawaan yang berisik
        printQRInTerminal: false, // Menggunakan Pairing Code, bukan QR
        auth: state,
        browser: Browsers.ubuntu('Chrome'), // Menyamarkan sebagai browser Chrome di Ubuntu
        markOnlineOnConnect: true,
        syncFullHistory: false
    });

    // Proses Request Pairing Code jika belum login
    if (!sock.authState.creds.registered) {
        setTimeout(async () => {
            try {
                let phoneNumber = fs.readFileSync('wanumber.txt', 'utf8').trim();
                phoneNumber = phoneNumber.replace(/[^0-9]/g, ''); // Pastikan hanya angka
                
                const code = await sock.requestPairingCode(phoneNumber);
                console.log(`\n======================================================`);
                console.log(`📞 KODE PAIRING WHATSAPP ANDA: ${code}`);
                console.log(`Silakan buka WhatsApp di HP Anda -> Perangkat Tertaut -> Tautkan Perangkat -> Tautkan dengan nomor telepon saja.`);
                console.log(`======================================================\n`);
            } catch (err) {
                console.error('Gagal mendapatkan kode pairing:', err);
            }
        }, 3000); // Jeda 3 detik memastikan koneksi stabil sebelum request kode
    }

    // Mengelola koneksi jaringan dan auto-reconnect
    sock.ev.on('connection.update', (update) => {
        const { connection, lastDisconnect } = update;
        if (connection === 'close') {
            const shouldReconnect = lastDisconnect.error?.output?.statusCode !== DisconnectReason.loggedOut;
            console.log('Koneksi terputus, mencoba menghubungkan kembali...', shouldReconnect);
            if (shouldReconnect) {
                startBot();
            }
        } else if (connection === 'open') {
            console.log('✅ Bot WhatsApp Berhasil Terhubung dan Berjalan!');
        }
    });

    // Menyimpan kredensial sesi setiap ada pembaruan
    sock.ev.on('creds.update', saveCreds);

    // FITUR UTAMA: Auto Reject Panggilan Suara dan Video (Call/VC)
    sock.ev.on('call', async (call) => {
        for (let c of call) {
            if (c.status === 'offer') {
                console.log(`❌ Menolak otomatis panggilan dari ${c.from}`);
                // Perintah menolak panggilan (berfungsi di versi terbaru Baileys)
                await sock.rejectCall(c.id, c.from);
                
                // Mengirim pesan konfirmasi ke orang yang menelpon
                await sock.sendMessage(c.from, { 
                    text: ' *Pesan Otomatis*\n\nMohon maaf, sistem secara otomatis menolak panggilan suara atau video. Silakan kirim pesan teks. Terima kasih!' 
                });
            }
        }
    });

    // FITUR: Pesan masuk tetap dibiarkan agar notifikasi di HP Anda tetap bunyi
    sock.ev.on('messages.upsert', async m => {
        // Blok ini dibiarkan kosong
        // Karena kita tidak menggunakan perintah sock.readMessages(),
        // sistem WhatsApp tidak akan menganggap pesan sudah dibaca oleh bot.
        // Hasilnya: HP Anda akan tetap berdering secara normal saat ada pesan masuk.
    });
}

// Menjalankan Bot
startBot();
EOF

# 10. Memulai Bot di latar belakang menggunakan PM2
echo "Menjalankan Bot dengan PM2..."
pm2 start index.js --name "wa-autoreject"
pm2 save

# 11. Konfigurasi PM2 agar otomatis berjalan saat VPS reboot / startup
echo "Menambahkan perintah ke system startup..."
sudo env PATH=$PATH:$(dirname $(which node)) $(which pm2) startup systemd -u $(whoami) --hp $(eval echo ~$(whoami))
pm2 save

# 12. Tampilkan Kode Pairing untuk User
echo "=========================================================="
echo "      INSTALASI SELESAI! BOT BERJALAN DI BACKGROUND       "
echo "=========================================================="
echo "Menyiapkan KODE PAIRING Anda dalam 5 detik..."
sleep 5

echo "Membuka log PM2 secara otomatis..."
echo "=========================================================="
echo "INFO: Jika Anda sudah melihat KODE PAIRING,"
echo "silakan masukkan kodenya ke aplikasi WhatsApp Anda."
echo "Setelah terhubung, Anda dapat menekan CTRL+C untuk keluar dari layar ini."
echo "Bot akan tetap berjalan selamanya secara otomatis di VPS Anda."
echo "=========================================================="

pm2 logs wa-autoreject
