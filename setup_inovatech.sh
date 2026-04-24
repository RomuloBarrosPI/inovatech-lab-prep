#!/usr/bin/env bash
# =============================================================================
# INOVATECH – Script de Configuração dos Projetos Base
# Versões FIXAS e verificadas em: 21/04/2026
#
# Execução: bash setup_inovatech.sh  (de dentro de ~/inovatech ou qualquer dir)
#           curl -fsSL URL/setup_inovatech.sh | bash  (corpo ativo só ao final)
# Sistema alvo: Ubuntu 22.04 / 24.04 LTS (Python de sistema: 3.12 via
#   python3.12 — não depende do que python ou python3 apontam)
#
# NOTA SOBRE REPRODUTIBILIDADE:
#   Todas as versões abaixo são exatas (==X.Y.Z), garantindo que qualquer
#   execução deste script — em qualquer máquina, em qualquer data futura —
#   instale exatamente os mesmos pacotes verificados na data acima.
# NOTA: não são criados atalhos no desktop. Comandos (hash, versões) via
#       terminal, com cwd em ~/inovatech, conforme instrução da prova.
#
# Execução via pipe (curl … | bash):
#   Toda a lógica que altera o sistema fica em run_inovatech_setup, definida
#   antes e chamada só ao final. Se o download do script for interrompido,
#   o bash tende a falhar na análise (função incompleta) antes de executar
#   qualquer passo destrutivo — evitando meio-setup por corte de conexão.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Cores para output
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${RESET} $*"; }
error()   { echo -e "${RED}[ERRO]${RESET}  $*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}\n"; }

SETUP_DATE="2026-04-21"
# Intérprete do lab: sempre 3.12 (PATH); nunca python/python3 genéricos.
PYTHON312_CMD="python3.12"

check_cmd() {
  command -v "$1" &>/dev/null || error "Comando '$1' não encontrado. Instale antes de continuar."
}

# Cria venv e instala pacotes com versões exatas (usa UV definido no setup).
create_python_venv() {
  local project_dir="$1"
  shift
  local packages=("$@")

  info "Criando venv em ${project_dir}/.venv ..."
  "$UV" venv "${project_dir}/.venv" \
    --python "${PYTHON312:?}" --quiet

  info "Instalando ${#packages[@]} pacotes (versões fixas)..."
  "$UV" pip install \
    --python "${project_dir}/.venv/bin/python" \
    "${packages[@]}" \
    --quiet

  success "Ambiente Python configurado."
}

# ===========================================================================
# VERSÕES FIXAS – verificadas em 21/04/2026
# Critério de escolha documentado em cada bloco.
# ===========================================================================

# ── Python / Django ──────────────────────────────────────────────────────────
# Django 5.2.13  → série LTS (suporte até abril/2028). Não usamos 6.0.4
#                  pois é major muito recente, com breaking changes.
# DRF 3.17.1     → última estável da série 3.x
# SimpleJWT 5.5.1→ última estável; API estável conhecida pelos candidatos
DJANGO_PACKAGES=(
  "django==5.2.13"
  "djangorestframework==3.17.1"
  "djangorestframework-simplejwt==5.5.1"
  "django-filter==25.2"
  "django-cors-headers==4.9.0"
  "drf-spectacular==0.29.0"
  "asgiref==3.11.1"
  "sqlparse==0.5.5"
)

# ── Python / FastAPI ─────────────────────────────────────────────────────────
# fastapi 0.136.0 → última estável verificada
# sqlmodel 0.0.38 → última estável (subiu muito desde 0.0.21 do script anterior)
# alembic 1.18.4  → última estável
# pyjwt 2.9.0     → NÃO vem com FastAPI; deve ser instalado explicitamente
# python-jose 3.5.0 → alternativa ao pyjwt; ambos disponibilizados.
#                    Extra [cryptography] necessário para RS256, ES256 e demais
#                    algoritmos assimétricos. Sem ele, apenas HS256/384/512.
# passlib 1.7.4   → hash de senhas; NÃO vem com FastAPI
# bcrypt 3.2.2    → backend de hash do passlib. FIXADO em 3.x: bcrypt >= 4.0
#                  removeu __about__, quebrando passlib 1.7.4. bcrypt 3.2.2
#                  é a última versão plenamente compatível com passlib.
# python-multipart 0.0.26 → obrigatório para OAuth2PasswordRequestForm no FastAPI
FASTAPI_PACKAGES=(
  "fastapi==0.136.0"
  "uvicorn==0.45.0"
  "starlette==1.0.0"
  "sqlmodel==0.0.38"
  "alembic==1.18.4"
  "SQLAlchemy==2.0.49"
  "Mako==1.3.11"
  "pyjwt==2.9.0"
  "python-jose[cryptography]==3.5.0"  # [cryptography] habilita RS256, ES256 etc.
  "passlib==1.7.4"
  "bcrypt==3.2.2"           # ATENÇÃO: passlib 1.7.4 é incompatível com bcrypt >= 4.0.0
                             # (bcrypt 4.0 removeu __about__ que o passlib usa internamente)
                             # 3.2.2 é a última versão da série 3.x, totalmente compatível.
  "python-multipart==0.0.26"
  "email-validator==2.3.0"
  "httpx==0.28.1"
  "anyio==4.13.0"
  "pydantic==2.13.3"
  "pydantic-settings==2.14.0"
  "annotated-types==0.7.0"
)

# ── Node.js / Express ─────────────────────────────────────────────────────────
# express 4.21.2  → FIXADO em 4.x intencionalmente.
#                   Express 5.2.1 existe mas tem breaking changes (tratamento
#                   de erros async, remoção de métodos depreciados). A grande
#                   maioria dos candidatos conhece a API do Express 4.
# typeorm 0.3.28  → última estável da série 0.3.x (API estável)
# bcryptjs 2.4.3  → FIXADO em 2.x; versão 3.x tem API diferente
# typescript 5.8.3→ FIXADO em 5.x; TypeScript 6.x lançado recentemente,
#                   ainda pouco coberto em cursos/materiais de estudo
# @types/express  → 4.17.21 alinhado com Express 4 (não 5.x)
EXPRESS_PROD_PKGS=(
  "express@4.21.2"
  "typeorm@0.3.28"
  "better-sqlite3@12.9.0"
  "reflect-metadata@0.2.2"
  "jsonwebtoken@9.0.3"
  "bcryptjs@2.4.3"
  "cors@2.8.6"
  "dotenv@17.4.2"
  "class-validator@0.15.1"
  "class-transformer@0.5.1"
)
EXPRESS_DEV_PKGS=(
  "typescript@5.8.3"
  "ts-node@10.9.2"
  "ts-node-dev@2.0.0"
  "@types/express@4.17.21"
  "@types/node@22.15.3"
  "@types/jsonwebtoken@9.0.10"
  "@types/bcryptjs@2.4.6"
  "@types/cors@2.8.19"
  "@types/better-sqlite3@7.6.13"
  "rimraf@5.0.10"
)

# ── Node.js / Vite + Frontends ────────────────────────────────────────────────
# vite 5.4.14    → FIXADO em 5.x; Vite 8.x existe mas é muito recente
# `npm create vite@X` instala o pacote npm create-vite@X (versões publicadas
# separadas de vite). Não use VITE_VERSION aqui — seria notarget (ex. 5.4.14).
# react 18.3.1   → FIXADO em 18.x; React 19 tem breaking changes (novo JSX
#                  transform obrigatório, remoção de APIs legadas)
# react-router-dom 6.30.3 → v6 amplamente adotada; v7 tem mudanças de API.
#                          6.30.3 corrige XSS via Open Redirect (CVE na 6.30.0).
VITE_VERSION="5.4.14"
CREATE_VITE_VERSION="5.5.5"
REACT_VERSION="18.3.1"
REACT_TYPES_VERSION="18.3.12"
REACT_ROUTER_VERSION="6.30.3"
AXIOS_VERSION="1.15.2"
TS_VERSION="5.8.3"

# ===========================================================================
# Setup ativo: corpo principal (invocado só ao final — seguro para curl|bash).
# ===========================================================================

run_inovatech_setup() {
BASE_DIR="$(pwd)"

header "INOVATECH – Setup dos Projetos Base (versões fixas de ${SETUP_DATE})"
info "Diretório raiz: ${BASE_DIR}"

# ---------------------------------------------------------------------------
# 1. Verificar dependências do sistema
# ---------------------------------------------------------------------------
header "Verificando dependências do sistema"

check_cmd "${PYTHON312_CMD}"
PYTHON312="$(command -v "${PYTHON312_CMD}")" \
  || error "Não foi possível resolver o caminho de ${PYTHON312_CMD}."

PYTHON_VERSION=$("$PYTHON312" --version | awk '{print $2}')
info "Python  : ${PYTHON_VERSION} (${PYTHON312})"

"$PYTHON312" -c "import sys; sys.exit(0 if sys.version_info[:2] == (3, 12) else 1)" \
  || error "Python 3.12.x é obrigatório. Encontrado: ${PYTHON_VERSION}"

# ---------------------------------------------------------------------------
# 2. Instalar uv se não disponível (logo após validar Python 3.12; não
#    depende de Node/nvm — evita esperar download do Node antes dos venvs)
# ---------------------------------------------------------------------------
header "Verificando uv (gerenciador de ambientes Python)"

if ! command -v uv &>/dev/null; then
  info "Instalando uv (via ${PYTHON312} -m pip)..."
  "$PYTHON312" -m pip install --user uv --quiet
  export PATH="$HOME/.local/bin:$PATH"
fi

UV=$(command -v uv)
success "uv: $(uv --version)"

# ---------------------------------------------------------------------------
# 3. Garantir Node.js 22 via nvm — independente do Node do sistema
#
# Por que nvm e não o Node do sistema?
#   O Node instalado no Ubuntu varia por máquina (18, 20, 22...). Para
#   garantir que TODOS os laboratórios usem exatamente a mesma versão
#   documentada nas notas técnicas (22.x LTS), instalamos o nvm e
#   ativamos Node 22 para esta sessão e para sessões futuras do usuário.
#   O Node do sistema não é alterado nem removido.
# ---------------------------------------------------------------------------
header "Garantindo Node.js 22 LTS via nvm"

NODE_TARGET_MAJOR="22"
NVM_VERSION="0.40.3"          # versão do nvm a instalar se ausente
NVM_DIR="${HOME}/.nvm"

# ── 1. Instalar nvm se ainda não existe ─────────────────────────────────────
if [ ! -s "${NVM_DIR}/nvm.sh" ]; then
  info "nvm não encontrado. Instalando nvm ${NVM_VERSION}..."
  # Download do script de instalação oficial do nvm via curl ou wget
  if command -v curl &>/dev/null; then
    curl -fsSL \
      "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" \
      | bash
  elif command -v wget &>/dev/null; then
    wget -qO- \
      "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" \
      | bash
  else
    error "curl ou wget é necessário para instalar o nvm."
  fi
  success "nvm instalado em ${NVM_DIR}"
else
  info "nvm já presente em ${NVM_DIR}"
fi

# ── 2. Carregar nvm na sessão atual ─────────────────────────────────────────
export NVM_DIR="${NVM_DIR}"
# shellcheck source=/dev/null
\. "${NVM_DIR}/nvm.sh"

# ── 3. Instalar e ativar Node 22 LTS ────────────────────────────────────────
info "Instalando/ativando Node.js ${NODE_TARGET_MAJOR} LTS..."
nvm install "${NODE_TARGET_MAJOR}" --lts --no-progress 2>&1 | grep -v "^$" || true
nvm use "${NODE_TARGET_MAJOR}" > /dev/null
nvm alias default "${NODE_TARGET_MAJOR}" > /dev/null   # padrão para novas sessões

NODE_VERSION=$(node --version | tr -d 'v')
NPM_VERSION=$(npm --version)
NODE_MAJOR=$(echo "${NODE_VERSION}" | cut -d. -f1)

if [ "${NODE_MAJOR}" != "${NODE_TARGET_MAJOR}" ]; then
  error "Esperado Node.js ${NODE_TARGET_MAJOR}.x, mas ativo é ${NODE_VERSION}."
fi

success "Node.js : ${NODE_VERSION} (via nvm, major ${NODE_TARGET_MAJOR} conforme NT 03/2026)"
success "npm     : ${NPM_VERSION}"

# ── 4. Criar .nvmrc no diretório do projeto ──────────────────────────────────
# Qualquer `nvm use` ou editor com suporte a nvm lerá este arquivo e
# ativará automaticamente a versão correta ao entrar na pasta do projeto.
echo "${NODE_TARGET_MAJOR}" > "${BASE_DIR}/.nvmrc"
success ".nvmrc criado em ${BASE_DIR}/.nvmrc → versão ${NODE_TARGET_MAJOR}"

# ---------------------------------------------------------------------------
# 4. Backend 1 – Django + DRF
#   Pacote do projeto: config/ (settings, urls, wsgi). App Django: core/
#   (não trocar: “app” como nome de projeto conflita com o termo “app” do Django).
# ---------------------------------------------------------------------------
header "Backend 1 – Django 5.2.13 + DRF 3.17.1"

DJANGO_DIR="${BASE_DIR}/backend-django"
mkdir -p "${DJANGO_DIR}"
create_python_venv "${DJANGO_DIR}" "${DJANGO_PACKAGES[@]}"

if [ ! -f "${DJANGO_DIR}/manage.py" ]; then
  info "Inicializando projeto Django..."
  "${DJANGO_DIR}/.venv/bin/django-admin" startproject config "${DJANGO_DIR}"

  cd "${DJANGO_DIR}"
  .venv/bin/python manage.py startapp core
  cd "${BASE_DIR}"

  cat >> "${DJANGO_DIR}/config/settings.py" << 'SETTINGS'

# ── INOVATECH ────────────────────────────────────────────────────────────────
INSTALLED_APPS += [
    'rest_framework',
    'rest_framework_simplejwt',
    'corsheaders',
    'drf_spectacular',
    'django_filters',
    'core',
]

MIDDLEWARE.insert(1, 'corsheaders.middleware.CorsMiddleware')
CORS_ALLOW_ALL_ORIGINS = True

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticatedOrReadOnly',
    ),
    'DEFAULT_FILTER_BACKENDS': [
        'django_filters.rest_framework.DjangoFilterBackend',
        'rest_framework.filters.SearchFilter',
        'rest_framework.filters.OrderingFilter',
    ],
    'DEFAULT_SCHEMA_CLASS': 'drf_spectacular.openapi.AutoSchema',
}

SPECTACULAR_SETTINGS = {'TITLE': 'INOVATECH API', 'VERSION': '1.0.0'}
SETTINGS

  success "Projeto Django criado em ${DJANGO_DIR}"
else
  warn "Django já existe, pulando inicialização."
fi

# ---------------------------------------------------------------------------
# 5. Backend 2 – FastAPI + SQLModel + Alembic
#   Pacote Python ``api/`` (routers, models, …). Em main.py a variável ``app``
#   é a instância FastAPI — nome distinto evita confusão com a pasta ``api/``.
# ---------------------------------------------------------------------------
header "Backend 2 – FastAPI 0.136.0 + SQLModel 0.0.38 + Alembic 1.18.4"

FASTAPI_DIR="${BASE_DIR}/backend-fastapi"
mkdir -p "${FASTAPI_DIR}"
create_python_venv "${FASTAPI_DIR}" "${FASTAPI_PACKAGES[@]}"

if [ ! -f "${FASTAPI_DIR}/main.py" ]; then
  info "Criando estrutura do projeto FastAPI..."
  mkdir -p "${FASTAPI_DIR}"/{api/{routers,models,schemas,services,core},alembic/versions}
  : > "${FASTAPI_DIR}/api/__init__.py"
  : > "${FASTAPI_DIR}/api/core/__init__.py"

  cat > "${FASTAPI_DIR}/main.py" << 'MAIN'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="INOVATECH API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
def health():
    return {"status": "ok"}
MAIN

  cat > "${FASTAPI_DIR}/api/core/database.py" << 'DB'
from sqlmodel import create_engine, Session, SQLModel

DATABASE_URL = "sqlite:///./database.db"
engine = create_engine(DATABASE_URL, echo=True)

def create_db_and_tables():
    SQLModel.metadata.create_all(engine)

def get_session():
    with Session(engine) as session:
        yield session
DB

  cat > "${FASTAPI_DIR}/alembic.ini" << 'INI'
[alembic]
script_location = alembic
sqlalchemy.url = sqlite:///./database.db
[loggers]
keys = root,sqlalchemy,alembic
[handlers]
keys = console
[formatters]
keys = generic
[logger_root]
level = WARN
handlers = console
qualname =
[logger_sqlalchemy]
level = WARN
handlers =
qualname = sqlalchemy.engine
[logger_alembic]
level = INFO
handlers =
qualname = alembic
[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic
[formatter_generic]
format = %(levelname)-5.5s [%(name)s] %(message)s
datefmt = %H:%M:%S
INI

  success "Projeto FastAPI criado em ${FASTAPI_DIR}"
else
  warn "FastAPI já existe, pulando inicialização."
fi

# ---------------------------------------------------------------------------
# 6. Backend 3 – Express + TypeORM
# ---------------------------------------------------------------------------
header "Backend 3 – Express 4.21.2 + TypeORM 0.3.28 + TypeScript 5.8.3"

EXPRESS_DIR="${BASE_DIR}/backend-express"
mkdir -p "${EXPRESS_DIR}"
cd "${EXPRESS_DIR}"

if [ ! -f "package.json" ]; then
  npm init -y --quiet > /dev/null

  info "Instalando dependências de produção..."
  npm install --save --save-exact --quiet "${EXPRESS_PROD_PKGS[@]}"

  info "Instalando dependências de desenvolvimento..."
  npm install --save-dev --save-exact --quiet "${EXPRESS_DEV_PKGS[@]}"

  cat > tsconfig.json << 'TSCONFIG'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": false,
    "esModuleInterop": true,
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "skipLibCheck": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
TSCONFIG

  mkdir -p src/{routes,entities,middlewares,controllers}

  cat > src/index.ts << 'INDEX'
import 'reflect-metadata';
import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
INDEX

  node -e "
    const fs = require('fs');
    const pkg = JSON.parse(fs.readFileSync('package.json'));
    pkg.scripts = {
      'dev': 'ts-node-dev --respawn --transpile-only src/index.ts',
      'build': 'rimraf dist && tsc',
      'start': 'node dist/index.js'
    };
    fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
  "

  success "Projeto Express criado em ${EXPRESS_DIR}"
else
  warn "Express já existe, pulando inicialização."
fi

cd "${BASE_DIR}"

# ---------------------------------------------------------------------------
# 7. Frontend 1 – Vite + TypeScript Vanilla
# ---------------------------------------------------------------------------
header "Frontend 1 – Vite ${VITE_VERSION} + TypeScript ${TS_VERSION} (Vanilla)"

VANILLA_DIR="${BASE_DIR}/frontend-vanilla"
# Só o nome relativo a BASE_DIR. Path absoluto aninha .../inovatech/Users/...
# e o nome do pacote fica errado. Relativo + npx --yes: sem confirmação nem
# prompt "Package name"; package.json "name" = pasta (ex. frontend-vanilla).
VANILLA_NAME="frontend-vanilla"

if [ ! -d "${VANILLA_DIR}" ]; then
  npx --yes "create-vite@${CREATE_VITE_VERSION}" "${VANILLA_NAME}" \
    --template vanilla-ts
  cd "${VANILLA_DIR}"
  npm install --quiet
  npm install --save-dev --save-exact "vite@${VITE_VERSION}" --quiet
  npm install --save --save-exact "axios@${AXIOS_VERSION}" --quiet
  success "Frontend Vanilla criado em ${VANILLA_DIR}"
  cd "${BASE_DIR}"
else
  warn "Frontend Vanilla já existe, pulando."
fi

# ---------------------------------------------------------------------------
# 8. Frontend 2 – Vite + TypeScript + React
# ---------------------------------------------------------------------------
header "Frontend 2 – Vite ${VITE_VERSION} + React ${REACT_VERSION} + TypeScript ${TS_VERSION}"

REACT_DIR="${BASE_DIR}/frontend-react"
REACT_NAME="frontend-react"

if [ ! -d "${REACT_DIR}" ]; then
  npx --yes "create-vite@${CREATE_VITE_VERSION}" "${REACT_NAME}" \
    --template react-ts
  cd "${REACT_DIR}"
  npm install --quiet
  npm install --save-dev --save-exact "vite@${VITE_VERSION}" --quiet
  npm install --save --save-exact \
    "axios@${AXIOS_VERSION}" \
    "react-router-dom@${REACT_ROUTER_VERSION}" \
    --quiet
  success "Frontend React criado em ${REACT_DIR}"
  cd "${BASE_DIR}"
else
  warn "Frontend React já existe, pulando."
fi

# ---------------------------------------------------------------------------
# 9. Criar pasta de entrega (vazia, pronta para o candidato)
# ---------------------------------------------------------------------------
header "Criando pasta de entrega"

ENTREGA_DIR="${BASE_DIR}/entrega"
mkdir -p "${ENTREGA_DIR}"
success "Pasta de entrega criada: ${ENTREGA_DIR}"

# ---------------------------------------------------------------------------
# 10. Embutir script inovatech-submit
#    O conteúdo é escrito inline aqui para que o setup seja um arquivo único.
# ---------------------------------------------------------------------------
header "Instalando comando inovatech-submit"

SUBMIT_BIN="/usr/local/bin/inovatech-submit"

cat > /tmp/inovatech-submit << 'SUBMIT_SCRIPT'
#!/usr/bin/env bash
# =============================================================================
# INOVATECH – Comprovante de Entrega do Candidato
# Executado pelo CANDIDATO ao finalizar a solução
#
# A pasta padrão “entrega” é renomeada na prova para entrega_##, sendo ##
# o código 01 a 40 atribuído a cada candidato (ordem na prova objetiva,
# divulgado em nota técnica). A detecção automática (sem --dir) aceita
# ~/inovatech/entrega (legado) ou exatamente uma pasta entrega_## (## de 01 a 40).
# Identificador do candidato: “código PP” (PP = prova prática) conforme a nota
# técnica — não se usa o termo inscrição.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${RESET} $*"; }
error()   { echo -e "${RED}[ERRO]${RESET}  $*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}======================================${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}======================================${RESET}\n"; }

# --dir: caminho explícito. Caso contrário, detecção em ~/inovatech/ (ver
# comentário no cabeçalho deste script).
ENTREGA_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) ENTREGA_DIR="$2"; shift 2 ;;
    *) error "Argumento desconhecido: $1" ;;
  esac
done

INV_ROOT="$(pwd)"
if [ -z "${ENTREGA_DIR}" ]; then
  cands=()
  if [ -d "${INV_ROOT}/entrega" ]; then
    cands+=("${INV_ROOT}/entrega")
  fi
  if [ -d "${INV_ROOT}" ]; then
    shopt -s nullglob
    for d in "${INV_ROOT}"/entrega_[0-9][0-9]; do
      [ -d "$d" ] || continue
      bname=$(basename "$d")
      code=${bname#entrega_}
      if [[ "${code}" =~ ^(0[1-9]|[1-3][0-9]|40)$ ]]; then
        cands+=("$d")
      fi
    done
    shopt -u nullglob
  fi
  nc=${#cands[@]}
  if [ "${nc}" -eq 0 ]; then
    error "Pasta de entrega não encontrada. Use ~/inovatech/entrega ou" \
" ~/inovatech/entrega_## (## de 01 a 40, conforme nota técnica), ou" \
" inovatech-submit --dir /caminho"
  elif [ "${nc}" -gt 1 ]; then
    error "Várias pastas de entrega em ${INV_ROOT}. Especifique:" \
" inovatech-submit --dir /caminho/para/sua/entrega_##"
  else
    ENTREGA_DIR="${cands[0]}"
  fi
fi

[ -d "${ENTREGA_DIR}" ] \
  || error "Pasta de entrega não encontrada: ${ENTREGA_DIR}"

COMPROVANTE_DIR="${ENTREGA_DIR}/.comprovante"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')
DATESTAMP=$(date '+%Y%m%d_%H%M%S')
mkdir -p "${COMPROVANTE_DIR}"

header "INOVATECH – Geração de Comprovante de Entrega"

echo -e "${BOLD}Informe seus dados para o comprovante:${RESET}"
echo ""
read -rp "  Código PP        : " CODIGO_PP
[ -z "${CODIGO_PP}" ] && error "Código PP não pode ser vazio."
read -rp "  Nome completo    : " CANDIDATO_NOME
[ -z "${CANDIDATO_NOME}" ] && error "Nome não pode ser vazio."

echo ""
info "Processando entrega de: ${CANDIDATO_NOME} (código PP: ${CODIGO_PP})"
info "Pasta analisada       : ${ENTREGA_DIR}"
info "Data/Hora             : ${TIMESTAMP}"
echo ""

list_files() {
  local dir="$1"
  find "${dir}" -type f \
    ! -path "*/.venv/*" \
    ! -path "*/node_modules/*" \
    ! -path "*/__pycache__/*" \
    ! -path "*/.git/*" \
    ! -path "*/*.pyc" \
    ! -path "*/*.pyo" \
    ! -path "*/dist/*" \
    ! -path "*/.comprovante/*" \
    ! -name "*.log" \
    ! -name ".DS_Store" \
    | sort
}

MANIFEST_FILE="${COMPROVANTE_DIR}/manifesto_entrega_${DATESTAMP}.txt"
COMPROVANTE_FILE="${COMPROVANTE_DIR}/comprovante_PP_${CODIGO_PP}_${DATESTAMP}.txt"

info "Calculando hashes dos arquivos entregues..."
echo ""

{
  echo "# =============================================================="
  echo "# INOVATECH – Manifesto de Entrega do Candidato"
  echo "# Candidato  : ${CANDIDATO_NOME}"
  echo "# Código PP  : ${CODIGO_PP}  (PP = prova prática, nota técnica)"
  echo "# Data/Hora  : ${TIMESTAMP}"
  echo "# Algoritmo  : SHA-256"
  echo "# =============================================================="
  echo ""
} > "${MANIFEST_FILE}"

ALL_HASHES=""
FILE_COUNT=0

while IFS= read -r filepath; do
  rel="${filepath#${ENTREGA_DIR}/}"
  file_hash=$(sha256sum "${filepath}" | awk '{print $1}')
  printf "%-64s  %s\n" "${file_hash}" "${rel}" >> "${MANIFEST_FILE}"
  ALL_HASHES="${ALL_HASHES}${file_hash}"
  FILE_COUNT=$((FILE_COUNT + 1))
done < <(list_files "${ENTREGA_DIR}")

ENTREGA_HASH=$(echo -n "${ALL_HASHES}" | sha256sum | awk '{print $1}')

{
  echo ""
  echo "# HASH RAIZ DA ENTREGA"
  echo "${ENTREGA_HASH}"
} >> "${MANIFEST_FILE}"

success "  ${FILE_COUNT} arquivos processados."
echo ""

{
  echo "=============================================================="
  echo "  INOVATECH – Comprovante de Entrega"
  echo "  Processo Seletivo – Residência em Inovação Tecnológica"
  echo "  Edital 30/2026 – GAB/REI/IFPI"
  echo "=============================================================="
  echo ""
  echo "  Candidato        : ${CANDIDATO_NOME}"
  echo "  Código PP        : ${CODIGO_PP}  (prova prática)"
  echo "  Data/Hora        : ${TIMESTAMP}"
  echo "  Arquivos         : ${FILE_COUNT} arquivos"
  echo ""
  echo "  HASH DA SUA ENTREGA"
  echo "  ────────────────────────────────────────────────────────────"
  echo "  ${ENTREGA_HASH}"
  echo "  ────────────────────────────────────────────────────────────"
  echo ""
  echo "  COMO USAR ESTE COMPROVANTE:"
  echo ""
  echo "  1. Anote ou fotografe o hash acima."
  echo "  2. Após a divulgação do resultado, solicite à Coordenação"
  echo "     o hash da pasta avaliada referente ao seu código PP."
  echo "  3. Se os hashes forem idênticos, o conteúdo avaliado é"
  echo "     exatamente o que você entregou."
  echo "  4. Em caso de divergência: inovatech@ifpi.edu.br"
  echo ""
  echo "  Manifesto salvo em: ${MANIFEST_FILE}"
  echo "=============================================================="
} > "${COMPROVANTE_FILE}"

header "COMPROVANTE GERADO"
cat "${COMPROVANTE_FILE}"

echo ""
warn "ATENÇÃO: Anote ou fotografe o hash antes de sair do computador."
warn "Arquivo salvo em: ${COMPROVANTE_FILE}"
echo ""
success "Comprovante gerado com sucesso."
SUBMIT_SCRIPT

# Instalar em /usr/local/bin (requer sudo ou root)
if [ "$(id -u)" -eq 0 ]; then
  cp /tmp/inovatech-submit "${SUBMIT_BIN}"
  chmod +x "${SUBMIT_BIN}"
  success "Comando instalado: ${SUBMIT_BIN}"
else
  warn "Setup não está rodando como root — tentando sudo para instalar o comando..."
  sudo cp /tmp/inovatech-submit "${SUBMIT_BIN}" \
    && sudo chmod +x "${SUBMIT_BIN}" \
    && success "Comando instalado: ${SUBMIT_BIN}" \
    || warn "Não foi possível instalar em /usr/local/bin; use" \
" /tmp/inovatech-submit (caminho completo)."
fi

# ---------------------------------------------------------------------------
# 11. Embutir script inovatech-seal
# ---------------------------------------------------------------------------
header "Instalando comando inovatech-seal"

SEAL_BIN="/usr/local/bin/inovatech-seal"

cat > /tmp/inovatech-seal << 'SEAL_SCRIPT'
#!/usr/bin/env bash
# =============================================================================
# INOVATECH – Selagem Oficial dos Projetos Base
# Executado pela COORDENAÇÃO antes do início da prova
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${RESET} $*"; }
error()   { echo -e "${RED}[ERRO]${RESET}  $*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}======================================${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}======================================${RESET}\n"; }

BASE_DIR="$(pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) BASE_DIR="$2"; shift 2 ;;
    *) error "Argumento desconhecido: $1" ;;
  esac
done

[ -d "${BASE_DIR}" ] || error "Diretório não encontrado: ${BASE_DIR}"

SEAL_DIR="${BASE_DIR}/.seal"
if [ -f "${SEAL_DIR}/hash_publico.txt" ]; then
  error "Selagem já foi concluída (existe ${SEAL_DIR}/hash_publico.txt)." \
" Não reexecute no ambiente de prova. Reinstale o ambiente (setup) apague" \
" a pasta .seal/ com cautela."
fi

TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')
DATESTAMP=$(date '+%Y%m%d_%H%M%S')
MANIFEST_FILE="${SEAL_DIR}/manifesto_${DATESTAMP}.txt"
HASH_FILE="${SEAL_DIR}/hash_publico.txt"

mkdir -p "${SEAL_DIR}"

PROJECT_DIRS=(
  "backend-django"
  "backend-fastapi"
  "backend-express"
  "frontend-vanilla"
  "frontend-react"
)

header "INOVATECH – Selagem dos Projetos Base"
info "Diretório base : ${BASE_DIR}"
info "Data/Hora      : ${TIMESTAMP}"
echo ""

info "Verificando projetos base..."
for proj in "${PROJECT_DIRS[@]}"; do
  dir="${BASE_DIR}/${proj}"
  if [ -d "${dir}" ]; then
    success "  ${proj}/"
  else
    error "Projeto não encontrado: ${dir}"
  fi
done
echo ""

list_files() {
  local dir="$1"
  find "${dir}" -type f \
    ! -path "*/.venv/*" \
    ! -path "*/node_modules/*" \
    ! -path "*/__pycache__/*" \
    ! -path "*/.git/*" \
    ! -path "*/*.pyc" \
    ! -path "*/*.pyo" \
    ! -path "*/dist/*" \
    ! -path "*/.seal/*" \
    ! -name "*.log" \
    ! -name ".DS_Store" \
    | sort
}

info "Gerando manifesto de hashes por arquivo..."
echo ""

{
  echo "# =============================================================="
  echo "# INOVATECH – Manifesto de Integridade dos Projetos Base"
  echo "# Gerado em  : ${TIMESTAMP}"
  echo "# Algoritmo  : SHA-256"
  echo "# =============================================================="
  echo ""
} > "${MANIFEST_FILE}"

ALL_HASHES=""

for proj in "${PROJECT_DIRS[@]}"; do
  dir="${BASE_DIR}/${proj}"
  echo "## Projeto: ${proj}" >> "${MANIFEST_FILE}"
  echo "" >> "${MANIFEST_FILE}"
  file_count=0
  while IFS= read -r filepath; do
    rel="${filepath#${BASE_DIR}/}"
    file_hash=$(sha256sum "${filepath}" | awk '{print $1}')
    printf "%-64s  %s\n" "${file_hash}" "${rel}" >> "${MANIFEST_FILE}"
    ALL_HASHES="${ALL_HASHES}${file_hash}"
    file_count=$((file_count + 1))
  done < <(list_files "${dir}")
  echo "" >> "${MANIFEST_FILE}"
  success "  ${proj}/ → ${file_count} arquivos"
done

ROOT_HASH=$(echo -n "${ALL_HASHES}" | sha256sum | awk '{print $1}')

{
  echo ""
  echo "# HASH RAIZ"
  echo "${ROOT_HASH}"
} >> "${MANIFEST_FILE}"

{
  echo "=============================================================="
  echo "  INOVATECH – Hash Oficial dos Projetos Base"
  echo "  Edital 30/2026 – GAB/REI/IFPI"
  echo "=============================================================="
  echo ""
  echo "  Data/Hora da Selagem : ${TIMESTAMP}"
  echo "  Algoritmo            : SHA-256 (hash raiz)"
  echo ""
  echo "  HASH PÚBLICO OFICIAL"
  echo "  ────────────────────────────────────────────────────────────"
  echo "  ${ROOT_HASH}"
  echo "  ────────────────────────────────────────────────────────────"
  echo ""
  echo "  Manifesto detalhado : ${MANIFEST_FILE}"
  echo "=============================================================="
} > "${HASH_FILE}"
cp "${HASH_FILE}" "${SEAL_DIR}/hash_publico_${DATESTAMP}.txt"

header "SELAGEM CONCLUÍDA"
cat "${HASH_FILE}"

echo ""
warn "Divulgue o HASH PÚBLICO OFICIAL aos candidatos antes do início da prova."
success "Selagem finalizada."

# Remoção do binário: reduz risco de nova selagem acidental. Não impede
# quem copiou o script; impede reexecução boba com o mesmo path.
if [ -e /usr/local/bin/inovatech-seal ]; then
  if [ -w /usr/local/bin ] 2>/dev/null; then
    rm -f /usr/local/bin/inovatech-seal
  elif command -v sudo &>/dev/null; then
    sudo rm -f /usr/local/bin/inovatech-seal 2>/dev/null || true
  fi
fi
rm -f /tmp/inovatech-seal 2>/dev/null || true
warn "O comando inovatech-seal foi removido. Para reinstalar a ferramenta" \
" (apenas em preparo de outro lab), execute setup_inovatech.sh de novo."
SEAL_SCRIPT

if [ "$(id -u)" -eq 0 ]; then
  cp /tmp/inovatech-seal "${SEAL_BIN}"
  chmod +x "${SEAL_BIN}"
  success "Comando instalado: ${SEAL_BIN}"
else
  sudo cp /tmp/inovatech-seal "${SEAL_BIN}" \
    && sudo chmod +x "${SEAL_BIN}" \
    && success "Comando instalado: ${SEAL_BIN}" \
    || warn "Não foi possível instalar inovatech-seal em /usr/local/bin."
fi

# ---------------------------------------------------------------------------
# 12. inovatech-versions — listar versões (candidato verifica o ambiente)
# ---------------------------------------------------------------------------
header "Instalando comando inovatech-versions"

VERSIONS_BIN="/usr/local/bin/inovatech-versions"

cat > /tmp/inovatech-versions << 'VERSIONS_SCRIPT'
#!/usr/bin/env bash
# INOVATECH – pacotes principais (leitura do ambiente em ~/inovatech)
# Sem set -e: o relatório deve listar tudo mesmo se pip estiver indisponível
# no venv (ex.: certos venvs uv) ou se um pip show falhar.
set -uo pipefail

BASE_DIR="${1:-$(pwd)}"
if [ ! -d "${BASE_DIR}" ]; then
  echo "Diretório não encontrado: ${BASE_DIR}" >&2
  exit 1
fi

# Segundo arg: nome do *distribution* p/ importlib.metadata (não o import).
py_show() {
  local venv_sub="$1" dist="$2" name="$3"
  local py="${BASE_DIR}/${venv_sub}/.venv/bin/python"
  if [ ! -x "${py}" ]; then
    echo "  ${name}: (sem .venv em ${venv_sub}/)"
    return
  fi
  local ver
  ver=$(
    "${py}" -c "
import importlib.metadata as m
try:
    print(m.version('${dist}'))
except m.PackageNotFoundError:
    raise SystemExit(1)
" 2>/dev/null
  ) || true
  if [ -z "${ver}" ]; then
    ver=$(
      "${py}" -m pip show "${dist}" 2>/dev/null | sed -n 's/^Version: //p' | head -1
    ) || true
  fi
  echo "  ${name}: ${ver:-?}"
}

# Lê versão declarada no package.json (ranges como ^1.2.3 ou ~1.2.3).
# Usado no backend-express onde os pacotes foram instalados com --save-exact,
# portanto os valores já são versões exatas sem ranges.
json_pkg() {
  local sub="$1"
  shift
  local j="${BASE_DIR}/${sub}/package.json"
  if [ ! -f "${j}" ]; then
    echo "  (package.json ausente em ${sub}/)"
    return
  fi
  python3.12 -c "
import json, sys
p = json.load(open(sys.argv[1], encoding='utf-8'))
d = {**p.get('dependencies', {}), **p.get('devDependencies', {})}
for k in sys.argv[2:]:
    if k in d:
        print('  ' + k + ': ' + d[k])
" "${j}" "$@"
}

# Lê versão RESOLVIDA do package-lock.json (versão exata instalada pelo npm).
# Usado nos frontends, cujos templates declaram ranges (^18.3.1, ~5.6.2, etc.).
# Fallback para package.json se o lockfile não existir (ex.: npm install
# ainda não foi executado).
lock_pkg() {
  local sub="$1"
  shift
  local lock="${BASE_DIR}/${sub}/package-lock.json"
  local json="${BASE_DIR}/${sub}/package.json"
  if [ -f "${lock}" ]; then
    python3.12 -c "
import json, sys
lock = json.load(open(sys.argv[1], encoding='utf-8'))
pkgs = lock.get('packages', {})
for k in sys.argv[2:]:
    key = 'node_modules/' + k
    if key in pkgs:
        print('  ' + k + ': ' + pkgs[key].get('version', '?'))
    else:
        print('  ' + k + ': (não encontrado no lockfile)')
" "${lock}" "$@"
  elif [ -f "${json}" ]; then
    echo "  (lockfile ausente em ${sub}/ — lendo ranges do package.json)"
    python3.12 -c "
import json, sys
p = json.load(open(sys.argv[1], encoding='utf-8'))
d = {**p.get('dependencies', {}), **p.get('devDependencies', {})}
for k in sys.argv[2:]:
    if k in d:
        print('  ' + k + ': ' + d[k] + '  (range — execute npm install)')
" "${json}" "$@"
  else
    echo "  (package.json e package-lock.json ausentes em ${sub}/)"
  fi
}

echo "INOVATECH – versões principais (base: ${BASE_DIR})"
echo ""

# ── Carregar nvm se disponível, para que node/npm reflitam a versão correta ──
export NVM_DIR="${HOME}/.nvm"
# shellcheck source=/dev/null
[ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh" --no-use

# Ativar a versão definida no .nvmrc do projeto (criado pelo setup)
NVMRC="${BASE_DIR}/.nvmrc"
NVM_TARGET=""
if [ -f "${NVMRC}" ]; then
  NVM_TARGET=$(cat "${NVMRC}" | tr -d '[:space:]')
  if command -v nvm &>/dev/null 2>&1; then
    nvm use "${NVM_TARGET}" > /dev/null 2>&1 || true
  fi
fi

NODE_VER=$(node --version 2>/dev/null || echo '?')
NODE_MAJOR=$(echo "${NODE_VER}" | tr -d 'v' | cut -d. -f1)
NVM_LABEL=""
if [ -n "${NVM_TARGET}" ]; then
  if [ "${NODE_MAJOR}" = "${NVM_TARGET}" ]; then
    NVM_LABEL=" (nvm ✔ major ${NVM_TARGET})"
  else
    NVM_LABEL=" (nvm alvo: ${NVM_TARGET} — ATENÇÃO: node ativo é ${NODE_VER})"
  fi
fi

if command -v python3.12 &>/dev/null; then
  echo "Sistema: $(python3.12 --version 2>&1) | node ${NODE_VER}${NVM_LABEL} | npm $(npm --version 2>/dev/null || echo '?')"
else
  echo "Sistema: python3.12 ? | node ${NODE_VER}${NVM_LABEL} | npm $(npm --version 2>/dev/null || echo '?')"
fi
echo ""
echo "backend-django (importlib, fallback pip no .venv):"
py_show backend-django Django django
py_show backend-django djangorestframework djangorestframework
py_show backend-django djangorestframework_simplejwt "djangorestframework-simplejwt"
py_show backend-django drf_spectacular drf-spectacular
py_show backend-django django_filter django-filter
py_show backend-django django_cors_headers django-cors-headers
echo ""
echo "backend-fastapi (importlib, fallback pip no .venv):"
py_show backend-fastapi fastapi fastapi
py_show backend-fastapi uvicorn uvicorn
py_show backend-fastapi sqlmodel sqlmodel
py_show backend-fastapi alembic alembic
py_show backend-fastapi SQLAlchemy SQLAlchemy
echo ""
echo "backend-express (package.json, versões exatas — instalado com --save-exact):"
json_pkg backend-express express typeorm typescript better-sqlite3 \
  jsonwebtoken bcryptjs
echo ""
echo "frontend-vanilla (package-lock.json, versões resolvidas):"
lock_pkg frontend-vanilla vite typescript axios
echo ""
echo "frontend-react (package-lock.json, versões resolvidas):"
lock_pkg frontend-react vite typescript react react-dom "@vitejs/plugin-react" \
  "@types/react" "@types/react-dom" react-router-dom axios
echo ""
VERSIONS_SCRIPT

if [ "$(id -u)" -eq 0 ]; then
  cp /tmp/inovatech-versions "${VERSIONS_BIN}"
  chmod +x "${VERSIONS_BIN}"
  success "Comando instalado: ${VERSIONS_BIN}"
else
  sudo cp /tmp/inovatech-versions "${VERSIONS_BIN}" \
    && sudo chmod +x "${VERSIONS_BIN}" \
    && success "Comando instalado: ${VERSIONS_BIN}" \
    || warn "Não foi possível instalar inovatech-versions em /usr/local/bin."
fi

# ---------------------------------------------------------------------------
# 13. Relatório final com versões exatas instaladas
# ---------------------------------------------------------------------------
header "Configuração concluída — Resumo das versões instaladas"

echo -e "${BOLD}Projetos criados em: ${BASE_DIR}${RESET}"
echo ""
echo -e "  ${GREEN}✔${RESET}  ${BOLD}backend-django/${RESET}"
echo "       django==5.2.13 (LTS) | djangorestframework==3.17.1"
echo "       djangorestframework-simplejwt==5.5.1 | drf-spectacular==0.29.0"
echo "       django-filter==25.2 | django-cors-headers==4.9.0"
echo ""
echo -e "  ${GREEN}✔${RESET}  ${BOLD}backend-fastapi/${RESET}"
echo "       fastapi==0.136.0 | uvicorn==0.45.0 | starlette==1.0.0"
echo "       sqlmodel==0.0.38 | alembic==1.18.4 | SQLAlchemy==2.0.49"
echo "       pyjwt==2.9.0 | python-jose[cryptography]==3.5.0"
echo "       passlib==1.7.4 | bcrypt==3.2.2 | python-multipart==0.0.26"
echo ""
echo -e "  ${GREEN}✔${RESET}  ${BOLD}backend-express/${RESET}"
echo "       express@4.21.2 | typeorm@0.3.28 | better-sqlite3@12.9.0"
echo "       jsonwebtoken@9.0.3 | bcryptjs@2.4.3 | typescript@5.8.3"
echo "       @types/express@4.17.21 | ts-node-dev@2.0.0"
echo ""
echo -e "  ${GREEN}✔${RESET}  ${BOLD}frontend-vanilla/${RESET}"
echo "       vite@${VITE_VERSION} | typescript@${TS_VERSION} | axios@${AXIOS_VERSION}"
echo ""
echo -e "  ${GREEN}✔${RESET}  ${BOLD}frontend-react/${RESET}"
echo "       vite@${VITE_VERSION} | react@${REACT_VERSION} | typescript@${TS_VERSION}"
echo "       react-router-dom@${REACT_ROUTER_VERSION} | axios@${AXIOS_VERSION}"
echo ""
echo -e "${BOLD}Node.js:${RESET}"
echo "       Versão ativa : ${NODE_VERSION} (via nvm, major ${NODE_TARGET_MAJOR})"
echo "       nvm default  : ${NODE_TARGET_MAJOR} (permanente para o usuário)"
echo "       .nvmrc       : ${BASE_DIR}/.nvmrc → ${NODE_TARGET_MAJOR}"
echo "       O Node do sistema NÃO foi alterado."
echo ""
warn "Express fixado em 4.21.2 (não 5.x) — Express 5 tem breaking changes."
warn "React fixado em 18.3.1 (não 19.x) — React 19 tem breaking changes."
warn "TypeScript fixado em 5.8.3 (não 6.x) — TS 6 ainda muito recente."
warn "Vite fixado em 5.4.14 (não 8.x) — alinhado com o ecossistema React 18."
warn "Django fixado em 5.2.13 LTS (não 6.x) — série LTS mais estável."
echo ""
echo -e "${BOLD}Comandos (execute no terminal, em ${BASE_DIR}):${RESET}"
echo ""
echo -e "  ${GREEN}✔${RESET}  ${BOLD}inovatech-versions${RESET}  → confere versões do ambiente (candidato)"
echo -e "  ${GREEN}✔${RESET}  ${BOLD}inovatech-submit${RESET}  → gera comprovante (candidato)"
echo -e "  ${GREEN}✔${RESET}  ${BOLD}inovatech-seal${RESET}    → selagem única; após o sucesso o binário" \
" é removido (evita nova selagem acidental; reinstale o setup p/ outro lab)"
echo ""
echo -e "${BOLD}Como iniciar cada projeto:${RESET}"
echo ""
echo -e "  ${CYAN}Django :${RESET}  cd backend-django && source .venv/bin/activate"
echo "            python manage.py migrate && python manage.py runserver"
echo ""
echo -e "  ${CYAN}FastAPI:${RESET}  cd backend-fastapi && source .venv/bin/activate"
echo "            uvicorn main:app --reload"
echo ""
echo -e "  ${CYAN}Express:${RESET}  cd backend-express && npm run dev"
echo ""
echo -e "  ${CYAN}Vanilla:${RESET}  cd frontend-vanilla && npm run dev"
echo ""
echo -e "  ${CYAN}React  :${RESET}  cd frontend-react && npm run dev"
echo ""
echo -e "${BOLD}Ordem de uso (terminal, a partir de ${BASE_DIR}):${RESET}"
echo ""
echo -e "  ${CYAN}0.${RESET} Candidato pode rodar: ${BOLD}inovatech-versions${RESET} p/ checar" \
" dependências (opcional, antes ou durante a prova)."
echo ""
echo -e "  ${CYAN}1. Coordenação${RESET} roda ${BOLD}inovatech-seal${RESET} (padrão"
echo "     em ~/inovatech; use --dir /caminho se necessário), divulga o hash"
echo "     público; em seguida o binário é removido (uma selagem por ambiente)."
echo ""
echo -e "  ${CYAN}2. Candidatos${RESET} desenvolvem em entrega (renomeada na prova"
echo "     para entrega_##, 01 a 40, nota técnica). inovatech-submit ajusta a"
echo "     pasta sozinho se houver uma só; senão, inovatech-submit --dir …/entrega_##"
echo ""
echo -e "  ${CYAN}3. Ao encerrar${RESET}, cada candidato: ${BOLD}inovatech-submit${RESET}, informa" \
" nome e código PP, e anota o hash."
echo ""
success "Setup INOVATECH finalizado — ${SETUP_DATE}"
}

run_inovatech_setup "$@"
