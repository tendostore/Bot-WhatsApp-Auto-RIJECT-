#!/bin/bash

HIJAU='\033[0;32m'
BIRU='\033[0;34m'
KUNING='\033[1;33m'
NORMAL='\033[0m'

clear
echo -e "${BIRU}==============================================${NORMAL}"
echo -e "${HIJAU}   AUTO-INSTALL WA BOT ANTI-CALL (PPOB FIX)   ${NORMAL}"
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

const processedCalls = new Set(); 

async function startBot() {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info_baileys');
    const { version } = await fetchLatestBaileysVersion();

    const sock = makeWASocket({
        version,
        logger: pino({ level: 'silent' }),
        printQRInTerminal: false,
        markOnlineOnConnect: false, 
        syncFullHistory: false, // <-- FIX BARU: Bot tidak akan mensinkronisasi riwayat chat
        generateHighQualityLinkPreview: false,
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

    sock.ev.on('connection.update', (update) => {
        const { connection, lastDisconnect } = update;
        if (connection === 'close') {
            const shouldReconnect = lastDisconnect.error?.output?.statusCode !== DisconnectReason.loggedOut;
            if (shouldReconnect) startBot();
        } else if (connection === 'open') {
            console.log('✅ Bot Berhasil Terhubung!');
        }
    });

    sock.ev.on('call', async (node) => {
        for (let call of node) {
            if (call.status === 'offer') {
                if (processedCalls.has(call.id)) continue;
                processedCalls.add(call.id);

                const callerId = call.from; 
                const cleanNumber = callerId.split('@')[0].split(':')[0];
                const cleanJid = cleanNumber + '@s.whatsapp.net';

                try {
                    await sock.rejectCall(call.id, callerId);
                    
                    setTimeout(async () => {
                        try {
                            await sock.sendMessage(cleanJid, { 
                                text: "⚠️ *PENGUMUMAN OTOMATIS*\nMohon maaf, saat ini kami tidak dapat menerima panggilan telepon. Silakan kirimkan pesan teks (chat) saja. Terima kasih." 
                            });
                        } catch (msgErr) {}
                    }, 1500);

                    setTimeout(() => processedCalls.delete(call.id), 60000);
                } catch (e) {}
            }
        }
    });
}

startBot();
EOF

npm install @whiskeysockets/baileys pino > /dev/null 2>&1
echo -e "${HIJAU}[*] Instalasi selesai! Memulai bot...${NORMAL}"
node index.js
