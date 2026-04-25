# Crie uma pasta no pen-drive (substitua o caminho do pen-drive pelo correto)
PENDRIVE="/media/$USER/NOME_DO_PENDRIVE"
mkdir -p "$PENDRIVE/inovatech_offline"

# 1. Copia o projeto base completo (com os .venv e node_modules)
cp -r ~/inovatech "$PENDRIVE/inovatech_offline/"

# 2. Copia o Node.js (nvm) para garantir a versão 22 offline
cp -r ~/.nvm "$PENDRIVE/inovatech_offline/nvm_backup"

# 3. Copia os 4 comandos oficiais para o pen-drive
cp /usr/local/bin/inovatech-seal "$PENDRIVE/inovatech_offline/"
cp /usr/local/bin/inovatech-submit "$PENDRIVE/inovatech_offline/"
cp /usr/local/bin/inovatech-verify "$PENDRIVE/inovatech_offline/"
cp /usr/local/bin/inovatech-versions "$PENDRIVE/inovatech_offline/"
