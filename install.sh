#!/bin/bash

HIJAU='\033[0;32m'
BIRU='\033[0;34m'
KUNING='\033[1;33m'
MERAH='\033[0;31m'
NORMAL='\033[0m'

clear
echo -e "${BIRU}==============================================${NORMAL}"
echo -e "${HIJAU}   AUTO-INSTALL WA BOT ANTI-CALL (PPOB & CONFIG) ${NORMAL}"
echo -e "${BIRU}==============================================${NORMAL}"

# 1. Update Node.js & Install PM2
echo -e "${KUNING}[*] Mengecek & Mengupdate sistem VPS...${NORMAL}"
if command -v node &> /dev/null; then
    NODE_VER=$(node -v | cut -d 'v' -f 2 | cut -d '.' -f 1)
else
    NODE_VER=0
fi

if [ "$NODE_VER" -lt 20 ]; then
    if command -v apt &> /dev/null; then
        apt-get update && apt-get install -y curl
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
    elif command -v pkg &> /dev/null; then
        pkg update -y && pkg install nodejs -y
    fi
fi

if ! command -v pm2 &> /dev/null; then
    echo -e "${KUNING}[*] Memasang PM2 secara global...${NORMAL}"
    npm install -g pm2 > /dev/null 2>&1
fi

# 2. Setup Folder & File
echo -e "${KUNING}[*] Menyiapkan folder bot...${NORMAL}"
rm -rf wa-bot-anticall
mkdir -p wa-bot-anticall
cd wa-bot-anticall

cat << 'EOF' > package.json
{
  "name": "wa-bot-anticall",
  "main": "index.js"
}
EOF

cat << 'EOF' > index.js
const { 
    default: makeWASocket, 
    useMultiFileAuthState, 
    DisconnectReason, 
    fetchLatestBaileysVersion, 
    makeCacheableSignalKeyStore 
} = require('@whiskeysockets/baileys');
const pino = require('pino');
const readline = require('readline');

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const question = (text) => new Promise((resolve) => rl.question(text, resolve));

const processedCalls = new Set(); 
const isSetupMode = process.env.SETUP_MODE === 'true'; // Deteksi apakah sedang proses instalasi awal

async function startBot() {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info_baileys');
    const { version } = await fetchLatestBaileysVersion();

    const sock = makeWASocket({
        version,
        logger: pino({ level: 'silent' }),
        printQRInTerminal: false,
        markOnlineOnConnect: false, // Jaga notifikasi HP tetap bunyi
        syncFullHistory: false, // Hemat RAM & tidak narik chat lama
        auth: {
            creds: state.creds,
            keys: makeCacheableSignalKeyStore(state.keys, pino({ level: 'silent' })),
        },
        browser: ["Ubuntu", "Chrome", "20.0.04"]
    });

    if (!sock.authState.creds.registered) {
        console.clear();
        console.log("========================================");
        console.log("   WHATSAPP BOT ANTI-CALL PAIRING");
        console.log("========================================\n");
        const phoneNumber = await question('Masukkan nomor WA (Contoh: 62812xxx): ');
        const code = await sock.requestPairingCode(phoneNumber.replace(/[^0-9]/g, ''));
        console.log(`\n> KODE PAIRING ANDA: ${code} <\n`);
        console.log("Masukkan kode di atas pada WhatsApp HP Anda.");
    }

    sock.ev.on('creds.update', saveCreds);

    sock.ev.on('connection.update', async (update) => {
        const { connection, lastDisconnect } = update;
        if (connection === 'close') {
            const shouldReconnect = lastDisconnect.error?.output?.statusCode !== DisconnectReason.loggedOut;
            if (shouldReconnect) startBot();
        } else if (connection === 'open') {
            console.log('\n✅ Bot Berhasil Terhubung!');
            await sock.sendPresenceUpdate('unavailable');
            
            // Jika sedang instalasi awal, matikan script untuk dioper ke PM2
            if (isSetupMode) {
                console.log('Memindahkan bot ke background (PM2) dalam 3 detik...');
                setTimeout(() => { process.exit(0); }, 3000); 
            }
        }
    });

    sock.ev.on('call', async (node) => {
        for (let call of node) {
            if (call.status === 'offer') {
                if (processedCalls.has(call.id)) continue;
                processedCalls.add(call.id);
                
                const callerJid = call.from;
                
                try {
                    // Tolak panggilan otomatis
                    await sock.rejectCall(call.id, callerJid);
                    
                    // Waktu dan Pesan OPSI 1
                    const timeNow = new Date().toLocaleTimeString('id-ID', { timeZone: 'Asia/Jakarta' });
                    const pesan = `⚠️ *PANGGILAN OTOMATIS DITOLAK*\nHalo! 🙏 Untuk mempercepat proses pengisian paket data dan pembuatan config, kami tidak menerima telepon. Silakan langsung ketik pesanan kamu di sini. Admin akan segera memprosesnya! 🚀\n\n_Ditolak pada: ${timeNow}_`;
                    
                    // Kirim pesan balasan
                    await sock.sendMessage(callerJid, { text: pesan });
                    
                    // Hapus memory panggilan setelah 10 detik
                    setTimeout(() => processedCalls.delete(call.id), 10000);
                } catch (e) {
                    console.log(`[!] Gagal memproses panggilan:`, e.message);
                }
            }
        }
    });
}
startBot();
EOF

# 3. Instalasi Modul
echo -e "${KUNING}[*] Menginstal library Baileys...${NORMAL}"
npm install @whiskeysockets/baileys pino > /dev/null 2>&1

# 4. Menjalankan Login Pertama (Mode Setup)
echo -e "${HIJAU}>>> MEMULAI PROSES LOGIN <<<${NORMAL}"
SETUP_MODE=true node index.js

# 5. Otomatisasi PM2
echo -e "${KUNING}[*] Mendaftarkan bot ke PM2 agar aktif 24 Jam...${NORMAL}"
pm2 delete bot-wa &> /dev/null
pm2 start index.js --name "bot-wa"
pm2 save
pm2 startup

clear
echo -e "${HIJAU}==============================================${NORMAL}"
echo -e "${HIJAU}      INSTALASI SELESAI & BOT AKTIF 24 JAM!   ${NORMAL}"
echo -e "${HIJAU}==============================================${NORMAL}"
echo -e "${BIRU}Status PM2:${NORMAL}"
pm2 status bot-wa
echo -e "\n${KUNING}Sekarang VPS atau Terminal sudah bisa Anda tutup. Bot akan terus berjalan menjaga toko Anda!${NORMAL}"

