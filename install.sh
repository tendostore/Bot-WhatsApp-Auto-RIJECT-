#!/bin/bash

HIJAU='\033[0;32m'
BIRU='\033[0;34m'
KUNING='\033[1;33m'
NORMAL='\033[0m'

clear
echo -e "${BIRU}==============================================${NORMAL}"
echo -e "${HIJAU}   AUTO-INSTALL WA BOT ANTI-CALL (ALL CALL)   ${NORMAL}"
echo -e "${BIRU}==============================================${NORMAL}"

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

rm -rf wa-bot-anticall
mkdir -p wa-bot-anticall
cd wa-bot-anticall

cat << 'EOF' > package.json
{
  "name": "wa-bot-anticall",
  "main": "index.js",
  "scripts": { "start": "node index.js" }
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

// Hanya menyimpan ID call agar bot tidak merespon 1 sinyal yang sama berulang kali
const processedCalls = new Set(); 

async function startBot() {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info_baileys');
    const { version } = await fetchLatestBaileysVersion();

    const sock = makeWASocket({
        version,
        logger: pino({ level: 'silent' }),
        printQRInTerminal: false,
        markOnlineOnConnect: false, 
        syncFullHistory: false, 
        auth: {
            creds: state.creds,
            keys: makeCacheableSignalKeyStore(state.keys, pino({ level: 'silent' })),
        },
        browser: ["Ubuntu", "Chrome", "20.0.04"]
    });

    if (!sock.authState.creds.registered) {
        console.clear();
        const phoneNumber = await question('Masukkan nomor WA (Contoh: 62812xxx): ');
        const code = await sock.requestPairingCode(phoneNumber.replace(/[^0-9]/g, ''));
        console.log(`\n> KODE PAIRING ANDA: ${code} <\n`);
    }

    sock.ev.on('creds.update', saveCreds);

    sock.ev.on('connection.update', async (update) => {
        const { connection, lastDisconnect } = update;
        if (connection === 'close') {
            const shouldReconnect = lastDisconnect.error?.output?.statusCode !== DisconnectReason.loggedOut;
            if (shouldReconnect) startBot();
        } else if (connection === 'open') {
            console.log('✅ Bot Berhasil Terhubung!');
            await sock.sendPresenceUpdate('unavailable');
        }
    });

    sock.ev.on('call', async (node) => {
        for (let call of node) {
            if (call.status === 'offer') {
                if (processedCalls.has(call.id)) continue;
                processedCalls.add(call.id);

                const callerJid = call.from;

                try {
                    // 1. Tolak Telepon Langsung
                    await sock.rejectCall(call.id, callerJid);
                    console.log(`[📞] Panggilan ditolak dari: ${callerJid.split('@')[0]}`);

                    // 2. Buat Pesan Unik Berdasarkan Waktu Detail
                    const timeNow = new Date().toLocaleTimeString('id-ID', { timeZone: 'Asia/Jakarta' });
                    const pesan = `⚠️ *PENGUMUMAN OTOMATIS*\nMohon maaf, saat ini kami tidak dapat menerima panggilan telepon. Silakan kirimkan pesan teks (chat) saja. Terima kasih.\n\n_Ditolak pada: ${timeNow}_`;
                    
                    // 3. Kirim Pesan Setiap Kali Ditelepon
                    await sock.sendMessage(callerJid, { text: pesan });
                    console.log(`[✉️] BERHASIL mengirim pesan ke ${callerJid.split('@')[0]}`);

                    // Bersihkan memori ID setelah 10 detik agar hemat RAM
                    setTimeout(() => processedCalls.delete(call.id), 10000);

                } catch (e) {
                    console.log(`[!] GAGAL memproses panggilan/pesan:`, e.message);
                }
            }
        }
    });
}

startBot();
EOF

npm install @whiskeysockets/baileys pino > /dev/null 2>&1
echo -e "${HIJAU}[*] Instalasi selesai! Memulai bot...${NORMAL}"
node index.js

