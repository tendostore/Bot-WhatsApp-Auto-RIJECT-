#!/bin/bash

# ==============================================================================
# Skrip Install Bot WhatsApp Auto Reject (Pairing Code) - FINAL FIX
# ==============================================================================

# 1. Pastikan tidak ada prompt / popup saat instalasi (Auto Yes mode)
export DEBIAN_FRONTEND=noninteractive

# Bersihkan layar sebelum mulai
clear
echo "=========================================================="
echo "       SETUP BOT WHATSAPP AUTO REJECT (CALL/VC)           "
echo "=========================================================="
echo "Memulai Proses Instalasi. Silakan duduk manis..."
echo "Sistem akan menginstal semuanya terlebih dahulu."
echo "=========================================================="

# 2. Update & Upgrade Sistem VPS
sudo apt-get update -y
sudo apt-get upgrade -y

# 3. Instal dependensi dasar
sudo apt-get install -y curl git build-essential tzdata

# 4. Instal Node.js (Versi LTS 20)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Update npm ke versi paling baru
sudo npm install -g npm@latest

# 5. Instal PM2 versi terbaru secara global
sudo npm install -g pm2@latest

# 6. Membuat direktori kerja bot
BOT_DIR="$HOME/bot-autoreject"
mkdir -p $BOT_DIR
cd $BOT_DIR

# 7. Inisialisasi Project dan Instal dependensi bot
npm init -y
npm install @whiskeysockets/baileys@latest pino@latest
npm update 

# HAPUS SESI LAMA: Memastikan instalasi bersih
rm -rf auth_info_baileys

# 8. Membuat file utama bot (index.js)
cat << 'EOF' > index.js
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason, Browsers } = require('@whiskeysockets/baileys');
const pino = require('pino');
const fs = require('fs');

async function startBot() {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info_baileys');

    const sock = makeWASocket({
        logger: pino({ level: 'silent' }),
        printQRInTerminal: false,
        auth: state,
        browser: Browsers.ubuntu('Chrome'),
        markOnlineOnConnect: true,
        syncFullHistory: false
    });

    if (!sock.authState.creds.registered) {
        setTimeout(async () => {
            try {
                let phoneNumber = fs.readFileSync('wanumber.txt', 'utf8').trim();
                phoneNumber = phoneNumber.replace(/[^0-9]/g, ''); 
                
                const code = await sock.requestPairingCode(phoneNumber);
                console.log(`\n======================================================`);
                console.log(`📞 KODE PAIRING ANDA: ${code}`);
                console.log(`Buka WA -> Perangkat Tertaut -> Tautkan dengan No. Telepon`);
                console.log(`======================================================\n`);
            } catch (err) {
                console.error('Gagal mendapatkan kode pairing:', err.message);
            }
        }, 6000); 
    }

    sock.ev.on('connection.update', (update) => {
        const { connection, lastDisconnect } = update;
        if (connection === 'close') {
            const shouldReconnect = lastDisconnect.error?.output?.statusCode !== DisconnectReason.loggedOut;
            if (shouldReconnect) {
                setTimeout(() => startBot(), 5000);
            }
        } else if (connection === 'open') {
            console.log('✅ Bot Berhasil Terhubung!');
        }
    });

    sock.ev.on('creds.update', saveCreds);

    sock.ev.on('call', async (call) => {
        for (let c of call) {
            if (c.status === 'offer') {
                console.log(`❌ Menolak panggilan dari ${c.from}`);
                await sock.rejectCall(c.id, c.from);
                await sock.sendMessage(c.from, { 
                    text: ' *Pesan Otomatis*\n\nMohon maaf, saya sedang tidak bisa menerima panggilan (Call/VC). Silakan kirim pesan teks saja. Terima kasih!' 
                });
            }
        }
    });

    sock.ev.on('messages.upsert', async m => {});
}

startBot();
EOF

# ==============================================================================
# 9. PENGINSTALAN SELESAI, SEKARANG MINTA NOMOR WHATSAPP
# ==============================================================================
echo ""
echo "=========================================================="
echo " PENGINSTALAN SELESAI! SEKARANG SETUP NOMOR WHATSAPP ANDA "
echo "=========================================================="
echo "Silakan masukkan nomor WhatsApp yang akan digunakan."
echo "Penting: Gunakan kode negara (misal: 628123456789)"

# Membaca input secara aman menggunakan /dev/tty
read -p "Nomor WhatsApp: " WA_NUMBER </dev/tty

if [[ -z "$WA_NUMBER" ]]; then
   echo "Error: Nomor WhatsApp tidak boleh kosong! Silakan jalankan ulang skrip."
   exit 1
fi

echo "$WA_NUMBER" > wanumber.txt

echo "=========================================================="
echo "Nomor disimpan: $WA_NUMBER"
echo "Mengatur Auto-Restart agar bot berjalan permanen..."
echo "=========================================================="

# 10. Konfigurasi PM2 agar bot otomatis jalan saat VPS Reboot
pm2 stop wa-autoreject 2>/dev/null
pm2 delete wa-autoreject 2>/dev/null
pm2 start index.js --name "wa-autoreject"
pm2 save

sudo env PATH=$PATH:$(dirname $(which node)) $(which pm2) startup systemd -u $(whoami) --hp $(eval echo ~$(whoami))
pm2 save

# 11. Selesai
echo "=========================================================="
echo "      BOT BERHASIL DIJALANKAN DI BACKGROUND               "
echo "=========================================================="
echo "Menunggu Kode Pairing muncul dalam 6 detik..."
sleep 6

pm2 logs wa-autoreject
