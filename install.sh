#!/bin/bash

# ==============================================================================
# Skrip Install Bot WhatsApp Auto Reject - VERSI CS TOKO (RAMAH & SOPAN)
# Fitur: Auto-Yes, Auto-Reboot, Offline Notif, Peringatan 1-2-3, & Auto-Unblock 15s
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

// Map untuk menyimpan jumlah panggilan dari setiap nomor
const spamCount = new Map();

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

    // AUTO REJECT CALL/VC DENGAN PESAN CS TOKO (RAMAH) & BLOKIR 15 DETIK
    sock.ev.on('call', async (call) => {
        for (let c of call) {
            if (c.status === 'offer') {
                console.log(`❌ Menolak panggilan dari ${c.from}`);
                
                // 1. Langsung tolak panggilan detik itu juga
                await sock.rejectCall(c.id, c.from);
                
                // 2. Hitung jumlah panggilan masuk dari nomor ini
                let currentCount = spamCount.get(c.from) || 0;
                currentCount++;
                spamCount.set(c.from, currentCount);

                if (currentCount === 1) {
                    // Panggilan Pertama: Pesan CS Toko Sopan
                    await sock.sendMessage(c.from, { 
                        text: 'Halo kak! 🙏\n\nMohon maaf sekali, saat ini kami hanya melayani via pesan teks (chat) agar semua pesanan dan pertanyaan pelanggan bisa terlayani dengan baik. \n\nSilakan ketikkan pesan kakak di sini ya. Terima kasih! 🛒✨' 
                    });
                } 
                else if (currentCount === 2) {
                    // Panggilan Kedua: Peringatan Halus dari Sistem
                    await sock.sendMessage(c.from, { 
                        text: '🤖 *Info Sistem Bot*\n\nMohon pengertiannya ya kak 🙏, sistem bot kami mendeteksi panggilan suara/video secara berulang. Silakan gunakan pesan teks saja ya kak agar sistem kami tidak error.\n\nJika panggilan dilanjutkan, sistem bot akan memblokir nomor kakak sementara.' 
                    });
                } 
                else if (currentCount >= 3) {
                    // Panggilan Ketiga: Blokir Otomatis dengan Pesan Mohon Maaf
                    console.log(`🚨 AUTO-BLOCK: Memblokir nomor ${c.from} selama 15 DETIK.`);
                    
                    await sock.sendMessage(c.from, { 
                        text: '🤖 *Sistem Auto-Block*\n\nMohon maaf kak, untuk menjaga kestabilan antrean chat kami, nomor ini telah diblokir sementara secara otomatis selama 15 detik karena panggilan beruntun. \n\nSilakan tinggalkan pesan teks setelah blokir terbuka ya kak. Terima kasih atas pengertiannya 🙏' 
                    });
                    
                    // Eksekusi pemblokiran nomor
                    await sock.updateBlockStatus(c.from, 'block');
                    
                    // Auto-Unblock setelah 15 DETIK (15000 milidetik)
                    setTimeout(async () => {
                        try {
                            await sock.updateBlockStatus(c.from, 'unblock');
                            console.log(`🔓 UNBANNED: Nomor ${c.from} telah dibuka blokirnya.`);
                            
                            // Reset hitungan spam kembali ke nol
                            spamCount.delete(c.from);
                        } catch (err) {
                            console.log(`Gagal unblock nomor ${c.from}:`, err.message);
                        }
                    }, 15000);
                }

                // Reset poin spam secara bertahap jika dia berhenti menelpon selama 5 menit
                setTimeout(() => {
                    let reduceCount = spamCount.get(c.from) || 0;
                    if (reduceCount > 0) {
                        spamCount.set(c.from, reduceCount - 1);
                    }
                }, 300000); 
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
