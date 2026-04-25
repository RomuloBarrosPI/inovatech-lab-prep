#!/usr/bin/env bash
# Script de Restauração Offline - INOVATECH
set -e

echo "=> Iniciando instalação offline..."

# 1. Restaurar pasta do projeto
if [ ! -d "$HOME/inovatech" ]; then
    echo "=> Copiando ~/inovatech..."
    cp -r inovatech "$HOME/inovatech"
else
    echo "=> Pasta ~/inovatech já existe, pulando cópia."
fi

# 2. Restaurar NVM (Node.js offline)
if [ ! -d "$HOME/.nvm" ]; then
    echo "=> Copiando ~/.nvm..."
    cp -r nvm_backup "$HOME/.nvm"
    
    # Adicionar ao .bashrc se não existir
    if ! grep -q "NVM_DIR" "$HOME/.bashrc"; then
        echo "=> Configurando NVM no .bashrc..."
        echo 'export NVM_DIR="$HOME/.nvm"' >> "$HOME/.bashrc"
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> "$HOME/.bashrc"
    fi
fi

# 3. Instalar os comandos globais (requer sudo)
echo "=> Instalando comandos inovatech-* em /usr/local/bin..."
sudo cp inovatech-seal inovatech-submit inovatech-verify inovatech-versions /usr/local/bin/
sudo chmod +x /usr/local/bin/inovatech-*

echo "======================================================"
echo " Instalação Concluída!"
echo " Feche este terminal e abra um novo para carregar o Node."
echo " Vá para ~/inovatech e teste rodando: inovatech-verify"
echo "======================================================"
