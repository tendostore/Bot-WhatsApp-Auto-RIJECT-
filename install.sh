#!/bin/bash

# ==============================================================================
# Skrip Install Bot WhatsApp Auto Reject (Pairing Code) - FIX KONEKSI TERPUTUS
# ==============================================================================

export DEBIAN_FRONTEND=noninteractive

clear
echo "=========================================================="
echo "       SETUP BOT WHATSAPP AUTO REJECT (CALL/VC)           "
echo "=========================================================="
echo "Memulai Proses Instalasi. Silakan duduk manis..."
echo "Sistem akan menginstal semuanya terlebih dahulu."
echo "=========================================================="

sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y curl git build-essential tzdata

curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

sudo npm install -g npm@latest
sudo npm install -g pm2@latest

BOT_DIR="$HOME/bot-autoreject"
mkdir -p $BOT_DIR
cd $BOT_DIR

npm init -y
npm install @whiskeysockets/baileys@latest pino@latest
npm update 

# HAPUS SESI LAMA: Memastikan instalasi bersih
rm -rf auth_info_baileys

# Membuat file utama bot (index.js)
cat << 'EOF' > index.js
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason, Browsers, fetchLatestBaileysVersion } = require('@whiskeysockets/baileys');
const pino = require('pino');
const fs = require('fs');

process.on('uncaughtException', console.error);

async function startBot() {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info_baileys');
    
    // Sinkronisasi versi WA Web terbaru agar tidak ditendang oleh server
    const { version, isLatest } = await fetchLatestBaileysVersion();
    console.log(`Menggunakan versi WA Web: v${version.join('.')}`);

    const sock = makeWASocket({
        version, // Gunakan versi terbaru
        logger: pino({ level: 'silent' }),
        printQRInTerminal: false,
        auth: state,
        browser: Browsers.ubuntu('Chrome'),
        markOnlineOnConnect: true,
        syncFullHistory: false
    });

    if (!sock.authState.creds.registered) {
        // Jeda 5 detik agar koneksi benar-benar rileks sebelum request kode
        setTimeout(async () => {
            try {
                let phoneNumber = fs.readFileSync('wanumber.txt', 'utf8').trim();
                phoneNumber = phoneNumber.replace(/[^0-9]/g, ''); 
                
                console.log('Meminta Kode Pairing ke Server WhatsApp...');
                const code = await sock.requestPairingCode(phoneNumber);
                const formattedCode = code?.match(/.{1,4}/g)?.join('-') || code;
                
                console.log(`\n======================================================`);
                console.log(`📞 KODE PAIRING ANDA: ${formattedCode}`);
                console.log(`Buka WA -> Perangkat Tertaut -> Tautkan dengan No. Telepon`);
                console.log(`======================================================\n`);
            } catch (err) {
                console.log('Gagal request kode pairing:', err.message);
            }
        }, 5000); 
    }

    sock.ev.on('connection.update', (update) => {
        const { connection, lastDisconnect } = update;

        if (connection === 'close') {
            const statusCode = lastDisconnect.error?.output?.statusCode;
            const errorMsg = lastDisconnect.error?.message || "Unknown Error";
            console.log(`Koneksi terputus. (Kode: ${statusCode} - ${errorMsg})`);
            
            const shouldReconnect = statusCode !== DisconnectReason.loggedOut;
            if (shouldReconnect) {
                console.log('Mencoba menghubungkan kembali dalam 5 detik...');
                setTimeout(() => startBot(), 5000);
            } else {
                console.log('Sesi telah Logout. Silakan jalankan ulang skrip untuk login baru.');
            }
        } else if (connection === 'open') {
            console.log('✅ Bot Berhasil Terhubung ke WhatsApp!');
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

echo ""
echo "=========================================================="
echo " PENGINSTALAN SELESAI! SEKARANG SETUP NOMOR WHATSAPP ANDA "
echo "=========================================================="
echo "Silakan masukkan nomor WhatsApp yang akan digunakan."
echo "Penting: Gunakan kode negara (misal: 628123456789)"

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

pm2 stop wa-autoreject 2>/dev/null
pm2 delete wa-autoreject 2>/dev/null
pm2 start index.js --name "wa-autoreject"
pm2 save

sudo env PATH=$PATH:$(dirname $(which node)) $(which pm2) startup systemd -u $(whoami) --hp $(eval echo ~$(whoami))
pm2 save

echo "=========================================================="
echo "      BOT BERHASIL DIJALANKAN DI BACKGROUND               "
echo "=========================================================="
echo "Menunggu Kode Pairing muncul..."
sleep 4

pm2 logs wa-autoreject
