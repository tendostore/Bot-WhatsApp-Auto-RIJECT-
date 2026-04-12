#!/bin/bash

# ==============================================================================
# Skrip Install Bot WhatsApp Auto Reject (Pairing Code) - UPDATE SEMUA MODUL
# Fitur: Auto-Yes, Auto-Reboot, Anti-428 Error, Notifikasi Tetap Bunyi, & Update Modul
# ==============================================================================

# 1. Pastikan tidak ada prompt / popup saat instalasi (Auto Yes mode)
export DEBIAN_FRONTEND=noninteractive

# Bersihkan layar sebelum mulai
clear
echo "=========================================================="
echo "       SETUP BOT WHATSAPP AUTO REJECT (CALL/VC)           "
echo "=========================================================="

# OTOMATIS MEMINTA NOMOR WHATSAPP DI AWAL
echo "Silakan masukkan nomor WhatsApp yang akan digunakan."
echo "Penting: Gunakan kode negara (misal: 628123456789)"
read -p "Nomor WhatsApp: " WA_NUMBER

# Validasi input sederhana
if [[ -z "$WA_NUMBER" ]]; then
   echo "Error: Nomor WhatsApp tidak boleh kosong!"
   exit 1
fi

echo "=========================================================="
echo "Nomor disimpan: $WA_NUMBER"
echo "Memulai Proses Instalasi. Semua akan berjalan otomatis..."
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

# 5. Instal PM2 versi terbaru secara global untuk proses background & auto-reboot
sudo npm install -g pm2@latest

# 6. Membuat direktori kerja bot
BOT_DIR="$HOME/bot-autoreject"
mkdir -p $BOT_DIR
cd $BOT_DIR

# 7. Simpan nomor WA ke file agar bisa dibaca oleh bot
echo "$WA_NUMBER" > wanumber.txt

# 8. Inisialisasi Project dan Instal dependensi bot (SELALU VERSI TERBARU)
npm init -y
npm install @whiskeysockets/baileys@latest pino@latest
npm update # Memastikan semua sub-modul juga diperbarui ke versi paling stabil

# HAPUS SESI LAMA: Memastikan instalasi bersih
rm -rf auth_info_baileys

# 9. Membuat file utama bot (index.js)
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

    // Proses Request Pairing Code
    if (!sock.authState.creds.registered) {
        // Jeda 6 detik agar koneksi WebSocket stabil (Mencegah Error 428)
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

    // AUTO REJECT CALL/VC
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

    // NOTIFIKASI TETAP BUNYI (Pesan tidak otomatis di-read)
    sock.ev.on('messages.upsert', async m => {
        // Biarkan kosong agar pesan tetap berstatus 'Unread' di HP
    });
}

startBot();
EOF

# 10. Konfigurasi PM2 agar bot otomatis jalan saat VPS Reboot
echo "Mengatur Auto-Restart (PM2)..."
pm2 stop wa-autoreject 2>/dev/null
pm2 delete wa-autoreject 2>/dev/null
pm2 start index.js --name "wa-autoreject"
pm2 save

# Setup PM2 Startup
sudo env PATH=$PATH:$(dirname $(which node)) $(which pm2) startup systemd -u $(whoami) --hp $(eval echo ~$(whoami))
pm2 save

# 11. Selesai
echo "=========================================================="
echo "      INSTALASI SELESAI! BOT BERJALAN PERMANEN            "
echo "=========================================================="
echo "Menunggu Kode Pairing muncul..."
sleep 6
pm2 logs wa-autoreject
