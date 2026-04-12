#!/bin/bash

# ==============================================================================
# Skrip Install Bot WhatsApp Auto Reject (Pairing Code) - COOLDOWN 10 DETIK
# Fitur: Auto-Yes, Auto-Reboot, Anti-428, Offline Notif, & Anti-Spam Pesan
# ==============================================================================

export DEBIAN_FRONTEND=noninteractive

clear
echo "=========================================================="
echo "       SETUP BOT WHATSAPP AUTO REJECT (CALL/VC)           "
echo "=========================================================="
echo "Memulai Proses Instalasi. Silakan duduk manis..."
echo "Sistem akan menginstal semuanya terlebih dahulu."
echo "=========================================================="

# 1. Update & Upgrade Sistem VPS
sudo apt-get update -y
sudo apt-get upgrade -y

# 2. Instal dependensi dasar
sudo apt-get install -y curl git build-essential tzdata

# 3. Instal Node.js (Versi LTS 20)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Update npm ke versi paling baru
sudo npm install -g npm@latest

# 4. Instal PM2 versi terbaru
sudo npm install -g pm2@latest

# 5. Membuat direktori kerja bot
BOT_DIR="$HOME/bot-autoreject"
mkdir -p $BOT_DIR
cd $BOT_DIR

# 6. Inisialisasi Project dan Instal dependensi bot
npm init -y
npm install @whiskeysockets/baileys@latest pino@latest
npm update 

# HAPUS SESI LAMA: Memastikan instalasi bersih
rm -rf auth_info_baileys

# 7. Membuat file utama bot (index.js)
cat << 'EOF' > index.js
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason, Browsers, fetchLatestBaileysVersion } = require('@whiskeysockets/baileys');
const pino = require('pino');
const fs = require('fs');

process.on('uncaughtException', console.error);

// Set untuk menyimpan daftar nomor yang sedang dalam masa "Cooldown" (Anti-Spam)
const callCooldown = new Set();

async function startBot() {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info_baileys');
    const { version } = await fetchLatestBaileysVersion();

    const sock = makeWASocket({
        version,
        logger: pino({ level: 'silent' }),
        printQRInTerminal: false,
        auth: state,
        browser: Browsers.ubuntu('Chrome'),
        markOnlineOnConnect: false, 
        syncFullHistory: false
    });

    sock.ev.on('connection.update', async (update) => {
        const { connection, lastDisconnect, qr } = update;

        if (qr && !sock.authState.creds.registered) {
            setTimeout(async () => {
                try {
                    let phoneNumber = fs.readFileSync('wanumber.txt', 'utf8').trim();
                    phoneNumber = phoneNumber.replace(/[^0-9]/g, ''); 
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

        if (connection === 'close') {
            const statusCode = lastDisconnect.error?.output?.statusCode;
            if (statusCode !== DisconnectReason.loggedOut) {
                setTimeout(() => startBot(), 5000);
            }
        } else if (connection === 'open') {
            console.log('✅ Bot Terhubung! Status disetel ke Offline agar notif HP bunyi.');
            await sock.sendPresenceUpdate('unavailable');
        }
    });

    sock.ev.on('creds.update', saveCreds);

    // AUTO REJECT CALL/VC DENGAN ANTI-SPAM PESAN (10 DETIK)
    sock.ev.on('call', async (call) => {
        for (let c of call) {
            if (c.status === 'offer') {
                console.log(`❌ Menolak panggilan dari ${c.from}`);
                
                // Langsung tolak panggilan detik itu juga
                await sock.rejectCall(c.id, c.from);
                
                // Anti-Spam: Cek apakah nomor ini baru saja menelpon dalam 10 detik terakhir
                if (!callCooldown.has(c.from)) {
                    // Jika belum ada di daftar cooldown, kirim pesan peringatan otomatis
                    await sock.sendMessage(c.from, { 
                        text: ' *Pesan Otomatis*\n\nMohon maaf, saya sedang tidak bisa menerima panggilan. Silakan kirim pesan teks saja. Terima kasih!' 
                    });
                    
                    // Masukkan nomor tersebut ke daftar cooldown
                    callCooldown.add(c.from);
                    
                    // Hapus nomor dari daftar cooldown setelah 10 DETIK (10000 milidetik)
                    setTimeout(() => {
                        callCooldown.delete(c.from);
                    }, 10000);
                } else {
                    // Jika mencoba call berulang-ulang dalam waktu 10 detik, diamkan saja
                    console.log(`Diamkan (Anti-Spam): Orang ini (${c.from}) mencoba spam call.`);
                }
            }
        }
    });

    sock.ev.on('messages.upsert', async m => {
        // Biarkan kosong agar pesan tetap unread dan notifikasi HP berbunyi
    });
}

startBot();
EOF

# ==============================================================================
# 8. PENGINSTALAN SELESAI, SEKARANG MINTA NOMOR WHATSAPP
# ==============================================================================
echo ""
echo "=========================================================="
echo " PENGINSTALAN SELESAI! SEKARANG SETUP NOMOR WHATSAPP ANDA "
echo "=========================================================="
echo "Silakan masukkan nomor WhatsApp yang akan digunakan."
read -p "Nomor WhatsApp: " WA_NUMBER </dev/tty

if [[ -z "$WA_NUMBER" ]]; then
   echo "Error: Nomor WhatsApp tidak boleh kosong!"
   exit 1
fi

echo "$WA_NUMBER" > wanumber.txt

# 9. Konfigurasi PM2 Auto-Restart
pm2 stop wa-autoreject 2>/dev/null
pm2 delete wa-autoreject 2>/dev/null
pm2 start index.js --name "wa-autoreject"
pm2 save

sudo env PATH=$PATH:$(dirname $(which node)) $(which pm2) startup systemd -u $(whoami) --hp $(eval echo ~$(whoami))
pm2 save

# 10. Selesai
echo "=========================================================="
echo "      BOT BERHASIL DIJALANKAN DI BACKGROUND               "
echo "=========================================================="
echo "Menunggu Kode Pairing muncul..."
sleep 4
pm2 logs wa-autoreject
