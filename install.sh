#!/bin/bash

# ==============================================================================
# Skrip Install Bot WhatsApp Auto Reject - FIX LOGIKA & FORMAT BLOKIR
# Fitur: Auto-Yes, Auto-Reboot, CS Ramah, & Blokir Multi-Device Akurat
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

// Map untuk menyimpan jumlah panggilan dari setiap nomor agar akurat
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
            console.log('\n✅ BERHASIL! Bot sudah Terhubung ke WhatsApp Anda.');
            console.log('Status WhatsApp disetel ke Offline agar notifikasi HP tetap bunyi.\n');
            await sock.sendPresenceUpdate('unavailable');
        }
    });

    sock.ev.on('creds.update', saveCreds);

    // LOGIKA AUTO REJECT & BLOCK BERTAHAP
    sock.ev.on('call', async (call) => {
        for (let c of call) {
            if (c.status === 'offer') {
                const callerId = c.from; // Contoh: 62812xxx:1@s.whatsapp.net
                
                // MENGHAPUS KODE PERANGKAT (:1 dll) AGAR FORMAT BLOKIR DITERIMA SERVER WA
                const blockJid = callerId.split(':')[0] + '@s.whatsapp.net';
                
                console.log(`\n[CALL] Panggilan masuk dari: ${blockJid}`);
                
                // 1. Tolak panggilan secara instan
                await sock.rejectCall(c.id, callerId);
                
                // 2. Update hitungan spam
                let count = (spamCount.get(callerId) || 0) + 1;
                spamCount.set(callerId, count);
                
                console.log(`[STATUS] Akumulasi panggilan nomor ini: ${count}/3`);

                if (count === 1) {
                    await sock.sendMessage(callerId, { 
                        text: 'Halo kak! 🙏\n\nMohon maaf sekali, saat ini kami hanya melayani via pesan teks (chat) agar semua pertanyaan bisa terlayani dengan baik. \n\nSilakan ketikkan pesan kakak di sini ya. Terima kasih! 🛒✨' 
                    });
                } 
                else if (count === 2) {
                    await sock.sendMessage(callerId, { 
                        text: '🤖 *Info Sistem Bot*\n\nMohon pengertiannya ya kak 🙏, sistem mendeteksi panggilan berulang. Silakan gunakan pesan teks saja agar sistem tidak error.\n\nJika panggilan dilanjutkan (ke-3), sistem akan memblokir nomor kakak sementara.' 
                    });
                } 
                else if (count === 3) {
                    // HANYA EKSEKUSI 1 KALI TEPAT DI PANGGILAN KETIGA (Mencegah Spam Pesan Auto-Block)
                    console.log(`[ACTION] Memblokir ${blockJid} selama 15 detik...`);
                    
                    await sock.sendMessage(callerId, { 
                        text: '🤖 *Sistem Auto-Block*\n\nMohon maaf kak, nomor ini telah diblokir sementara selama 15 detik karena panggilan beruntun. \n\nSilakan tinggalkan pesan teks setelah blokir terbuka ya kak. Terima kasih 🙏' 
                    });
                    
                    // Eksekusi Blokir menggunakan JID yang sudah dibersihkan
                    try {
                        await sock.updateBlockStatus(blockJid, 'block');
                        console.log(`[BERHASIL] Server WA telah memblokir nomor tersebut.`);
                    } catch (err) {
                        console.log(`[GAGAL BLOKIR] Error: ${err.message}`);
                    }
                    
                    // Buka Blokir setelah 15 detik
                    setTimeout(async () => {
                        try {
                            await sock.updateBlockStatus(blockJid, 'unblock');
                            console.log(`[ACTION] Blokir dibuka untuk: ${blockJid}`);
                            spamCount.delete(callerId); // Reset hitungan
                        } catch (err) {
                            console.log(`[GAGAL UNBLOCK] Error: ${err.message}`);
                        }
                    }, 15000);
                }
                else if (count > 3) {
                    // Jika panggilan ke-4, 5 dst masih lolos, diamkan saja tanpa kirim pesan
                    console.log(`[ACTION] Panggilan ke-${count} ditolak instan (Menunggu eksekusi blokir server/sedang terblokir).`);
                }

                // Jika tidak ada panggilan lagi dalam 5 menit, reset hitungan peringatan 1/2
                setTimeout(() => {
                    if (spamCount.has(callerId) && spamCount.get(callerId) < 3) {
                        spamCount.delete(callerId);
                    }
                }, 300000);
            }
        }
    });

    sock.ev.on('messages.upsert', async m => {
        // Biarkan kosong agar notifikasi HP tetap prioritas
    });
}

startBot();
EOF

# ==============================================================================
# 8. INPUT NOMOR & SETUP PM2
# ==============================================================================
echo ""
echo "=========================================================="
echo " PENGINSTALAN SELESAI! SEKARANG SETUP NOMOR WHATSAPP ANDA "
echo "=========================================================="
read -p "Nomor WhatsApp (Contoh: 628123xxx): " WA_NUMBER </dev/tty

if [[ -z "$WA_NUMBER" ]]; then
   echo "Error: Nomor tidak boleh kosong!"
   exit 1
fi

echo "$WA_NUMBER" > wanumber.txt

# Pembersihan proses lama sebelum menjalankan yang baru
pm2 stop wa-autoreject 2>/dev/null
pm2 delete wa-autoreject 2>/dev/null
pm2 start index.js --name "wa-autoreject"
pm2 save

sudo env PATH=$PATH:$(dirname $(which node)) $(which pm2) startup systemd -u $(whoami) --hp $(eval echo ~$(whoami))
pm2 save

# 9. Tampilan Akhir & Log
clear
echo "=========================================================="
echo "      BOT BERHASIL DIJALANKAN DI BACKGROUND               "
echo "=========================================================="
echo "1. Buka WhatsApp -> Perangkat Tertaut."
echo "2. Pilih 'Tautkan dengan nomor telepon saja'."
echo "3. Masukkan kode pairing di bawah ini."
echo "=========================================================="
sleep 2
tail -f ~/.pm2/logs/wa-autoreject-out.log
