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
# Reexecução no laboratório (coordenação):
#   Ao rodar este script de novo na mesma pasta (ex.: ~/inovatech) que já foi
#   configurada, o setup detecta instalação anterior e APAGA .seal/, as pastas
#   dos cinco projetos base, entrega/ e entrega_##/, depois recria tudo — assim
#   a árvore acompanha a versão atual do script e inovatech-seal volta a ser
#   instalado em /usr/local/bin (selagens antigas são descartadas).
#   Para forçar esse reset: INOVATECH_LAB_RESET=1 bash setup_inovatech.sh
#   Para evitar o reset (ex.: desenvolvimento): INOVATECH_SKIP_LAB_RESET=1
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

inovatech_ascii_banner() {
  echo -e "${BOLD}${CYAN}"
  cat << 'INVASCII'
██╗███╗   ██╗ ██████╗ ██╗   ██╗ █████╗ ████████╗███████╗ ██████╗██╗  ██╗
██║████╗  ██║██╔═══██╗██║   ██║██╔══██╗╚══██╔══╝██╔════╝██╔════╝██║  ██║
██║██╔██╗ ██║██║   ██║██║   ██║███████║   ██║   █████╗  ██║     ███████║
██║██║╚██╗██║██║   ██║╚██╗ ██╔╝██╔══██║   ██║   ██╔══╝  ██║     ██╔══██║
██║██║ ╚████║╚██████╔╝ ╚████╔╝ ██║  ██║   ██║   ███████╗╚██████╗██║  ██║
╚═╝╚═╝  ╚═══╝ ╚═════╝   ╚═══╝  ╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚═════╝╚═╝  ╚═╝
INVASCII
  echo -e "${RESET}"
}

# Zera selagem, entregas e projetos base quando o assessor reexecuta o setup
# no mesmo diretório — BASE_DIR deve estar definido (run_inovatech_setup).
inovatech_maybe_reset_lab_tree() {
  if [ "${INOVATECH_SKIP_LAB_RESET:-}" = "1" ]; then
    info "INOVATECH_SKIP_LAB_RESET=1 — sem reset; árvore existente mantida."
    return 0
  fi

  local do_reset="0"
  if [ "${INOVATECH_LAB_RESET:-}" = "1" ]; then
    do_reset="1"
  elif [ -d "${BASE_DIR}/.seal" ]; then
    do_reset="1"
  elif [ -f "${BASE_DIR}/.nvmrc" ] \
    && [ -d "${BASE_DIR}/backend-django" ] \
    && [ -f "${BASE_DIR}/backend-django/manage.py" ]; then
    do_reset="1"
  fi

  if [ "${do_reset}" != "1" ]; then
    return 0
  fi

  header "Reset do laboratório (atualização / nova sessão)"
  warn "Instalação anterior detectada: removendo .seal/, entrega(s) e" \
       " projetos base para recriação conforme este script."

  if [ -d "${BASE_DIR}/.seal" ]; then
    rm -rf "${BASE_DIR}/.seal"
    success "Removida pasta .seal/ (selagens anteriores)."
  fi

  local proj
  for proj in backend-django backend-fastapi backend-express \
              frontend-vanilla frontend-react; do
    if [ -e "${BASE_DIR}/${proj}" ]; then
      rm -rf "${BASE_DIR:?}/${proj}"
      success "Removido ${proj}/"
    fi
  done

  if [ -d "${BASE_DIR}/entrega" ]; then
    rm -rf "${BASE_DIR}/entrega"
    success "Removido entrega/"
  fi

  local ed
  shopt -s nullglob
  for ed in "${BASE_DIR}"/entrega_[0-9][0-9]; do
    [ -d "${ed}" ] || continue
    rm -rf "${ed}"
    success "Removido $(basename "${ed}")/"
  done
  shopt -u nullglob

  success "Reset concluído; recriando ambiente a seguir."
}

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

GITHUB_RAW="https://raw.githubusercontent.com/RomuloBarrosPI/inovatech-lab-prep/main"

run_inovatech_setup() {
BASE_DIR="$(pwd)"

echo ""
inovatech_ascii_banner
echo ""
header "INOVATECH – Setup dos Projetos Base (versões fixas de ${SETUP_DATE})"
info "Diretório raiz: ${BASE_DIR}"

inovatech_maybe_reset_lab_tree

# ---------------------------------------------------------------------------
# 0. Baixar assets do repositório (IFPI + Copa — mesmos paths em main)
# ---------------------------------------------------------------------------
FETCH=""
if command -v curl &>/dev/null; then
  FETCH=curl
elif command -v wget &>/dev/null; then
  FETCH=wget
fi

for ASSET in logo-inovatech.png logo-copa-inovatech.png \
             logo-copa-inovatech-preto.png; do
  if [ ! -f "${BASE_DIR}/${ASSET}" ]; then
    info "Baixando ${ASSET}..."
    if [ "${FETCH}" = curl ]; then
      curl -fsSL "${GITHUB_RAW}/${ASSET}" \
        -o "${BASE_DIR}/${ASSET}" || true
    elif [ "${FETCH}" = wget ]; then
      wget -q "${GITHUB_RAW}/${ASSET}" \
        -O "${BASE_DIR}/${ASSET}" || true
    else
      warn "curl/wget indisponível; nenhum PNG será baixado do GitHub."
      break
    fi
    if [ -f "${BASE_DIR}/${ASSET}" ]; then
      success "${ASSET} baixado."
    else
      warn "Falha ao baixar ${ASSET}."
    fi
  else
    info "${ASSET} já presente em ${BASE_DIR}/"
  fi
done

# ---------------------------------------------------------------------------
# 1. Verificar / instalar Python 3.12 e dependências do sistema
#
# No Ubuntu 22.04 o Python padrão é 3.10. O 3.12 vem do PPA deadsnakes e
# precisa de pacotes extras (python3.12-venv, python3.12-dev) para que uv
# consiga criar venvs sem "No module named 'distutils'" (PEP 632).
# ---------------------------------------------------------------------------
header "Verificando dependências do sistema"

# ── 1a. Instalar python3.12 + pacotes de suporte se não existirem ────────
if ! command -v "${PYTHON312_CMD}" &>/dev/null; then
  info "${PYTHON312_CMD} não encontrado. Instalando via deadsnakes PPA..."
  if [ "$(id -u)" -ne 0 ]; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq software-properties-common
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3.12 python3.12-venv python3.12-dev
  else
    apt-get update -qq
    apt-get install -y -qq software-properties-common
    add-apt-repository -y ppa:deadsnakes/ppa
    apt-get update -qq
    apt-get install -y -qq python3.12 python3.12-venv python3.12-dev
  fi
  success "${PYTHON312_CMD} instalado via deadsnakes."
else
  # Garante que python3.12-venv está presente (evita "No module named
  # 'distutils'" / "'_tkinter'" ao criar venvs com uv).
  if ! "$PYTHON312_CMD" -c "import ensurepip" 2>/dev/null; then
    info "Módulo ensurepip ausente; instalando python3.12-venv..."
    if [ "$(id -u)" -ne 0 ]; then
      sudo apt-get install -y -qq python3.12-venv
    else
      apt-get install -y -qq python3.12-venv
    fi
    success "python3.12-venv instalado."
  fi
fi

check_cmd "${PYTHON312_CMD}"
PYTHON312="$(command -v "${PYTHON312_CMD}")" \
  || error "Não foi possível resolver o caminho de ${PYTHON312_CMD}."

PYTHON_VERSION=$("$PYTHON312" --version | awk '{print $2}')
info "Python  : ${PYTHON_VERSION} (${PYTHON312})"

"$PYTHON312" -c "import sys; sys.exit(0 if sys.version_info[:2] == (3, 12) else 1)" \
  || error "Python 3.12.x é obrigatório. Encontrado: ${PYTHON_VERSION}"

# zip(1): usado por inovatech-enviar-entrega (comissão, empacotar pasta de entrega)
if ! command -v zip &>/dev/null; then
  info "Instalando pacote zip..."
  if [ "$(id -u)" -ne 0 ]; then
    sudo apt-get update -qq && sudo apt-get install -y -qq zip
  else
    apt-get update -qq && apt-get install -y -qq zip
  fi
fi
command -v zip &>/dev/null || error "Comando zip necessário para inovatech-enviar-entrega."

# ---------------------------------------------------------------------------
# 2. Instalar uv se não disponível (logo após validar Python 3.12; não
#    depende de Node/nvm — evita esperar download do Node antes dos venvs)
#
# uv é instalado via script standalone (binário Rust) — não depende de pip
# nem de distutils/setuptools, evitando o "No module named 'distutils'"
# que ocorre em instalações mínimas do Python 3.12 (PEP 632).
# ---------------------------------------------------------------------------
header "Verificando uv (gerenciador de ambientes Python)"

if ! command -v uv &>/dev/null; then
  info "Instalando uv via instalador standalone..."
  if command -v curl &>/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  elif command -v wget &>/dev/null; then
    wget -qO- https://astral.sh/uv/install.sh | sh
  else
    error "curl ou wget é necessário para instalar o uv."
  fi
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi

UV=$(command -v uv) \
  || error "uv não encontrado após instalação. Verifique o PATH."
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
NODE_TARGET_EXACT="22.22.2"   # versão exata para reprodutibilidade
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

# ── 3. Instalar e ativar Node 22 LTS (versão exata) ─────────────────────────
# Versão exata garante mesma versão de npm → mesmos lock files
info "Instalando/ativando Node.js ${NODE_TARGET_EXACT} LTS..."
nvm install "${NODE_TARGET_EXACT}" --no-progress 2>&1 | grep -v "^$" || true
nvm use "${NODE_TARGET_EXACT}" > /dev/null
nvm alias default "${NODE_TARGET_EXACT}" > /dev/null

NODE_VERSION=$(node --version | tr -d 'v')
NPM_VERSION=$(npm --version)

if [ "${NODE_VERSION}" != "${NODE_TARGET_EXACT}" ]; then
  warn "Esperado Node.js ${NODE_TARGET_EXACT}, ativo é ${NODE_VERSION}."
  NODE_MAJOR=$(echo "${NODE_VERSION}" | cut -d. -f1)
  if [ "${NODE_MAJOR}" != "${NODE_TARGET_MAJOR}" ]; then
    error "Major ${NODE_MAJOR} difere do esperado ${NODE_TARGET_MAJOR}."
  fi
fi

success "Node.js : ${NODE_VERSION} (via nvm, exato ${NODE_TARGET_EXACT})"
success "npm     : ${NPM_VERSION}"

# ── 4. Criar .nvmrc no diretório do projeto ──────────────────────────────────
# Qualquer `nvm use` ou editor com suporte a nvm lerá este arquivo e
# ativará automaticamente a versão correta ao entrar na pasta do projeto.
echo "${NODE_TARGET_EXACT}" > "${BASE_DIR}/.nvmrc"
success ".nvmrc criado em ${BASE_DIR}/.nvmrc → versão ${NODE_TARGET_EXACT}"

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

  # SECRET_KEY fixa: django-admin startproject gera uma chave
  # aleatória a cada execução, o que impede reprodutibilidade
  # do hash de selagem. Valor fixo, seguro para ambiente de
  # prova (não é produção).
  FIXED_SECRET='django-insecure-inovatech-edital30-2026-chave-fixa-prova'
  python3 -c "
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]) / 'config' / 'settings.py'
t = p.read_text()
t = re.sub(
    r\"SECRET_KEY\s*=\s*['\\\"].*?['\\\"]\",
    \"SECRET_KEY = '\" + sys.argv[2] + \"'\",
    t,
)
p.write_text(t)
" "${DJANGO_DIR}" "${FIXED_SECRET}"

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

# Descomente e ajuste se precisar customizar o modelo de usuário.
# IMPORTANTE: deve ser definido ANTES da primeira migração.
# AUTH_USER_MODEL = 'core.User'
SETTINGS

  # ── Hello-world: Model Item ───────────────────────────────────────────────
  cat > "${DJANGO_DIR}/core/models.py" << 'MODELS'
from django.db import models


class Item(models.Model):
    name = models.CharField(max_length=120)
    description = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.name
MODELS

  cat > "${DJANGO_DIR}/core/serializers.py" << 'SERIALIZERS'
from rest_framework import serializers
from .models import Item


class ItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = Item
        fields = "__all__"
        read_only_fields = ("id", "created_at")
SERIALIZERS

  cat > "${DJANGO_DIR}/core/views.py" << 'VIEWS'
from rest_framework.generics import ListAPIView
from rest_framework.permissions import AllowAny
from .models import Item
from .serializers import ItemSerializer


class ItemListView(ListAPIView):
    queryset = Item.objects.all()
    serializer_class = ItemSerializer
    permission_classes = [AllowAny]
VIEWS

  cat > "${DJANGO_DIR}/core/urls.py" << 'CORE_URLS'
from django.urls import path
from .views import ItemListView

urlpatterns = [
    path("items/", ItemListView.as_view(), name="item-list"),
]
CORE_URLS

  cat > "${DJANGO_DIR}/config/urls.py" << 'CONFIG_URLS'
from django.contrib import admin
from django.urls import path, include
from drf_spectacular.views import (
    SpectacularAPIView,
    SpectacularSwaggerView,
)

urlpatterns = [
    path("admin/", admin.site.urls),
    path(
        "api/",
        include("core.urls"),
    ),
    path(
        "api/schema/",
        SpectacularAPIView.as_view(),
        name="schema",
    ),
    path(
        "api/docs/",
        SpectacularSwaggerView.as_view(url_name="schema"),
        name="swagger-ui",
    ),
]
CONFIG_URLS

  info "Aplicando migrations do hello-world..."
  cd "${DJANGO_DIR}"
  .venv/bin/python manage.py makemigrations core --verbosity 0
  # Django inclui timestamp no cabeçalho de migrations geradas
  # ("Generated by Django ... on YYYY-MM-DD HH:MM"), o que quebra
  # reprodutibilidade entre máquinas. Normalizamos para linha fixa.
  .venv/bin/python -c "
import pathlib

p = pathlib.Path('core/migrations/0001_initial.py')
t = p.read_text()
lines = t.splitlines()
if lines and lines[0].startswith('# Generated by Django '):
    lines[0] = '# INOVATECH: migration header normalized'
    p.write_text('\n'.join(lines) + '\n')
"
  .venv/bin/python manage.py migrate --verbosity 0
  cd "${BASE_DIR}"

  success "Projeto Django criado em ${DJANGO_DIR}"
else
  warn "Django já existe, pulando inicialização."
  cd "${DJANGO_DIR}"
  if [ -f "core/migrations/0001_initial.py" ]; then
    .venv/bin/python -c "
import pathlib

p = pathlib.Path('core/migrations/0001_initial.py')
t = p.read_text()
lines = t.splitlines()
if lines and lines[0].startswith('# Generated by Django '):
    lines[0] = '# INOVATECH: migration header normalized'
    p.write_text('\n'.join(lines) + '\n')
"
  fi
  cd "${BASE_DIR}"
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
  mkdir -p "${FASTAPI_DIR}"/api/{routers,models,schemas,services,core}
  : > "${FASTAPI_DIR}/api/__init__.py"
  : > "${FASTAPI_DIR}/api/core/__init__.py"
  : > "${FASTAPI_DIR}/api/schemas/__init__.py"
  : > "${FASTAPI_DIR}/api/services/__init__.py"

  cat > "${FASTAPI_DIR}/api/core/database.py" << 'DB'
from sqlmodel import create_engine, Session, SQLModel
from api.core.config import settings

engine = create_engine(settings.DATABASE_URL)


def create_db_and_tables():
    SQLModel.metadata.create_all(engine)


def get_session():
    with Session(engine) as session:
        yield session
DB

  cat > "${FASTAPI_DIR}/api/core/config.py" << 'CONFIG'
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str = "sqlite:///./database.db"
    SECRET_KEY: str = "inovatech-fastapi-secret-prova"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60


settings = Settings()
CONFIG

  # ── Hello-world: Model Item ───────────────────────────────────────────────
  cat > "${FASTAPI_DIR}/api/models/item.py" << 'ITEM_MODEL'
from sqlmodel import SQLModel, Field


class Item(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str
    description: str = ""
ITEM_MODEL

  : > "${FASTAPI_DIR}/api/models/__init__.py"
  : > "${FASTAPI_DIR}/api/routers/__init__.py"

  cat > "${FASTAPI_DIR}/api/routers/items.py" << 'ITEMS_ROUTER'
from fastapi import APIRouter, Depends
from sqlmodel import Session, select
from api.core.database import get_session
from api.models.item import Item

router = APIRouter(prefix="/api/items", tags=["items"])


@router.get("/")
def list_items(session: Session = Depends(get_session)):
    return session.exec(select(Item)).all()
ITEMS_ROUTER

  cat > "${FASTAPI_DIR}/main.py" << 'MAIN'
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from api.core.database import create_db_and_tables
from api.routers.items import router as items_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    yield


app = FastAPI(
    title="INOVATECH API",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(items_router)


@app.get("/health")
def health():
    return {"status": "ok"}
MAIN

  # Nota: Alembic está instalado no .venv mas não pré-configurado.
  # O create_db_and_tables() no lifespan é suficiente para a prova.
  # Candidatos que desejem usar Alembic podem inicializá-lo com:
  #   cd backend-fastapi && source .venv/bin/activate && alembic init alembic

  success "Projeto FastAPI criado em ${FASTAPI_DIR}"
else
  warn "FastAPI já existe, pulando inicialização."
fi

info "Gerando backend-fastapi/requirements.txt a partir do .venv ..."
# uv venv não instala o shim .venv/bin/pip — usar uv pip freeze (mesmo fluxo
# de create_python_venv / uv pip install).
"${UV}" pip freeze --python "${FASTAPI_DIR}/.venv/bin/python" \
  > "${FASTAPI_DIR}/requirements.txt"
success "requirements.txt do FastAPI atualizado."

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

  # ── Hello-world: Entity Item ──────────────────────────────────────────────
  cat > src/entities/Item.ts << 'ENTITY'
import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
} from "typeorm";

@Entity()
export class Item {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  name: string;

  @Column({ default: "" })
  description: string;
}
ENTITY

  cat > src/routes/items.ts << 'ROUTES'
import { Router, Request, Response } from "express";
import { AppDataSource } from "../data-source";
import { Item } from "../entities/Item";

const router = Router();
const repo = () => AppDataSource.getRepository(Item);

router.get("/", async (_req: Request, res: Response) => {
  const items = await repo().find();
  res.json(items);
});

export default router;
ROUTES

  cat > src/data-source.ts << 'DATASOURCE'
import { DataSource } from "typeorm";
import { Item } from "./entities/Item";

export const AppDataSource = new DataSource({
  type: "better-sqlite3",
  database: "database.db",
  synchronize: true,
  entities: [Item],
});
DATASOURCE

  cat > src/index.ts << 'INDEX'
import "reflect-metadata";
import express from "express";
import cors from "cors";
import { AppDataSource } from "./data-source";
import itemsRouter from "./routes/items";

const app = express();
app.use(cors());
app.use(express.json());

app.get("/health", (_req, res) =>
  res.json({ status: "ok" })
);
app.use("/api/items", itemsRouter);

const PORT = process.env.PORT || 3000;

AppDataSource.initialize().then(() => {
  app.listen(PORT, () =>
    console.log(`Server running on port ${PORT}`)
  );
});
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

  # ── Branding INOVATECH ──────────────────────────────────────────────────
  cp "${BASE_DIR}/logo-inovatech.png" public/logo-inovatech.png
  # Logos «Copa do Mundo InovaTech 2026» (opcionais junto ao setup no mesmo dir)
  for COPA in logo-copa-inovatech.png logo-copa-inovatech-preto.png; do
    if [[ -f "${BASE_DIR}/${COPA}" ]]; then
      cp "${BASE_DIR}/${COPA}" "public/${COPA}"
    else
      warn "Opcional: ${COPA} não encontrado — coloque-o em ${BASE_DIR}" \
        " para os logos aparecerem na página inicial dos frontends."
    fi
  done

  # ── Pasta de imagens de figurinhas (prova prática) ─────────────────────
  # As imagens devem ser colocadas aqui antes da prova. Candidatos
  # referenciam como /assets/figurinhas/nome_da_imagem.png no frontend.
  mkdir -p public/assets/figurinhas
  if [ -d "${BASE_DIR}/figurinhas" ]; then
    cp -r "${BASE_DIR}/figurinhas/"* public/assets/figurinhas/ 2>/dev/null || true
  fi

  cat > index.html << 'HTML'
<!DOCTYPE html>
<html lang="pt-BR">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <link rel="icon" type="image/png" href="/logo-inovatech.png" />
    <title>INOVATECH · InovaCup 2026</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.ts"></script>
  </body>
</html>
HTML

  cat > src/style.css << 'CSS'
:root {
  --navy: #1b2a4a;
  --navy-light: #2d4373;
  --gray-bg: #eef2f7;
  --white: #ffffff;
  --text: #333333;
  --text-muted: #6b7280;
  --green: #16a34a;
  --red: #dc2626;
  --radius: 12px;
}

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family:
    "Segoe UI",
    system-ui,
    -apple-system,
    sans-serif;
  background: linear-gradient(180deg, var(--gray-bg) 0%, #e8ecf4 100%);
  color: var(--text);
  min-height: 100vh;
  display: flex;
  justify-content: center;
  align-items: flex-start;
  padding: 2rem 1rem;
}

#app {
  max-width: 880px;
  width: 100%;
}

.header {
  text-align: center;
  margin-bottom: 1.5rem;
}

.brand-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: 1rem 2rem;
  margin-bottom: 0.85rem;
}

.brand-row .logo-ifpi {
  height: 56px;
  width: auto;
}

.brand-row .logo-copa {
  max-height: 76px;
  max-width: min(100%, 360px);
  width: auto;
  height: auto;
  object-fit: contain;
  flex-shrink: 0;
}

.exam-meta {
  font-size: 0.82rem;
  color: var(--text-muted);
  margin-bottom: 0.65rem;
  line-height: 1.5;
}

.header h1 {
  font-size: 1.2rem;
  color: var(--navy);
  font-weight: 700;
  letter-spacing: 0.02em;
  margin-top: 0.25rem;
}

.briefing {
  background: var(--white);
  border-radius: var(--radius);
  padding: 1.25rem 1.45rem;
  margin-bottom: 2rem;
  box-shadow:
    0 1px 3px rgba(0, 0, 0, 0.08),
    0 4px 14px rgba(27, 42, 74, 0.06);
  border: 1px solid rgba(27, 42, 74, 0.08);
}

.briefing h2 {
  font-size: 0.98rem;
  color: var(--navy);
  margin: 1.35rem 0 0.5rem;
  padding-bottom: 0.35rem;
  border-bottom: 1px solid #e5e7eb;
}

.briefing h2:first-child {
  margin-top: 0;
}

.briefing p,
.briefing li {
  font-size: 0.89rem;
  line-height: 1.56;
}

.briefing ul,
.briefing ol {
  padding-left: 1.35rem;
  margin: 0.45rem 0 0.35rem;
}

.briefing-note {
  font-size: 0.82rem;
  color: var(--text-muted);
  padding: 0.65rem 0.85rem;
  background: var(--gray-bg);
  border-radius: 8px;
  margin-top: 0.85rem;
  border-left: 3px solid var(--navy-light);
}

.lab-section {
  margin-top: 0.5rem;
}

.section-title {
  font-size: 1rem;
  color: var(--navy);
  font-weight: 700;
  margin-bottom: 0.65rem;
}

.lab-section .hint {
  font-size: 0.82rem;
  color: var(--text-muted);
  margin-bottom: 1rem;
  line-height: 1.5;
}

.cards {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 1.25rem;
}

.card {
  background: var(--white);
  border-radius: var(--radius);
  padding: 1.5rem;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
  transition:
    box-shadow 0.2s,
    transform 0.2s;
}

.card:hover {
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.12);
  transform: translateY(-2px);
}

.card h2 {
  font-size: 1rem;
  color: var(--navy);
  margin-bottom: 0.25rem;
}

.card .tech {
  font-size: 0.8rem;
  color: var(--text-muted);
  margin-bottom: 0.75rem;
}

.card .links {
  font-size: 0.78rem;
  background: var(--gray-bg);
  padding: 0.5rem 0.75rem;
  border-radius: 6px;
  color: var(--navy-light);
  margin-bottom: 0.75rem;
  word-break: break-all;
}

.card .links a {
  color: var(--navy-light);
}

.btn-fetch {
  display: inline-block;
  padding: 0.4rem 1rem;
  font-size: 0.8rem;
  border: 1px solid var(--navy);
  border-radius: 6px;
  background: var(--white);
  color: var(--navy);
  cursor: pointer;
  transition: background 0.15s;
}

.btn-fetch:hover {
  background: var(--navy);
  color: var(--white);
}

.result {
  margin-top: 0.5rem;
  font-size: 0.78rem;
  min-height: 1.2em;
}

.result.ok {
  color: var(--green);
}

.result.err {
  color: var(--red);
}

.briefing code,
.lab-section code {
  font-size: 0.85em;
  background: #f1f5f9;
  padding: 0.1em 0.35em;
  border-radius: 4px;
}

kbd {
  font-family: ui-monospace, monospace;
  font-size: 0.85em;
  background: #f1f5f9;
  padding: 0.15em 0.4em;
  border-radius: 4px;
  border: 1px solid #e2e8f0;
}

.footer-copa {
  margin-top: 2rem;
  padding: 1.35rem 1rem;
  background: linear-gradient(135deg, #1b2a4a 0%, #243a66 100%);
  text-align: center;
  border-radius: var(--radius);
}

.footer-copa img {
  max-height: 72px;
  width: auto;
}

.footer-caption {
  font-size: 0.75rem;
  color: rgba(255, 255, 255, 0.65);
  margin-top: 0.65rem;
}
CSS

  cat > src/main.ts << 'MAIN_TS'
import axios from "axios";
import "./style.css";

interface Backend {
  title: string;
  tech: string;
  api: string;
  docs: string;
}

const backends: Backend[] = [
  {
    title: "Django + DRF",
    tech: "Python 3.12 · Django 5.2 · REST Framework",
    api: "http://localhost:8000/api/items/",
    docs: "http://localhost:8000/api/docs/",
  },
  {
    title: "FastAPI + SQLModel",
    tech: "Python 3.12 · FastAPI · Pydantic v2",
    api: "http://localhost:8000/api/items/",
    docs: "http://localhost:8000/docs",
  },
  {
    title: "Express + TypeORM",
    tech: "Node.js 22 · TypeScript · SQLite",
    api: "http://localhost:3000/api/items",
    docs: "http://localhost:3000/health",
  },
];

function briefingHtml(): string {
  const lines = [
    '<article class="briefing">',
    '<h2>O que você vai construir</h2>',
    "<p>O <strong>Copa do Mundo InovaTech 2026: O Álbum das Lendas</strong> ",
    "é uma plataforma colaborativa para colecionadores de figurinhas de jogadores lendários ",
    "(contexto oficial da sua prova prática).</p>",
    "<p>Aplicação em <strong>API RESTful</strong> (backend) e <strong>interface web funcional </strong>",
    "(frontend), integradas, usando <strong>SQLite</strong> nas versões fixadas ",
    "(Notas Técnicas 03, 04 e 05).</p>",
    "<h2>2. Requisitos previstos no edital</h2>",
    "<p><strong>2.1 Autenticação e perfil:</strong> cadastro (nome, e-mail, senha), ",
    "login com token (JWT diferencial); rota autenticada <code>/me</code>.</p>",
    "<p><strong>2.2 Álbum:</strong> figurinhas com nome do jogador, bio, posição, tags de ",
    "raridade e imagem; cofre para ocultar da listagem pública sem excluir; visitantes só ",
    "veem nomes, sem detalhes.</p>",
    "<p><strong>2.3 Votação:</strong> um voto por figurinha (+1 Craque ou −1 Bagre); totais ",
    "e saldo; destaque visual verde ou vermelho no card.</p>",
    "<p><strong>2.4 Interação:</strong> comentários e likes com toggle (desfazer).</p>",
    "<h2>O que não entra nestes 3 h</h2>",
    "<ul>",
    "<li>Recuperação de senha por e-mail ou serviços externos.</li>",
    "<li>Editar figurinha depois de publicada (imutabilidade).</li>",
    "<li>Docker ou deploy em nuvem — entrega local.</li>",
    "</ul>",
    "<h2>Como começar a partir deste laboratório</h2>",
    "<ol>",
    "<li>Este pacote já contém backends e frontends exemplo (hello-world <code>/items</code>), ",
    "com versões pré-instaladas. Substitua esse esqueleto pela sua solução do Álbum.",
    "</li>",
    "<li>Use <kbd>python3.12</kbd> nos projetos Python; ative cada <code>.venv</code>; em Node ",
    "<code>nvm use</code> segundo o pacote gerado pelo setup.</li>",
    "<li>Rode seus servidores (um backend + seu front) e teste o fluxo ponta a ponta.</li>",
    "<li>Figurinhas estáticas: neste lab coloque arquivos em ",
    "<code>public/assets/figurinhas/</code> e referencie como ",
    "<code>/assets/figurinhas/nome.ext</code> (o edital pode citar <code>/assets/cards/</code> — ",
    "ajuste o caminho se a banca exigir exatamente essa pasta).</li>",
    "<li>No terminal, rode <code>inovatech-preparar-entrega</code>: ele copia seu backend e ",
    "frontend para <code>entrega_##</code> e recria <code>.venv</code>/<code>node_modules</code> ",
    "automaticamente. Desenvolva a partir daí.</li>",
    "<li>Ao terminar, rode <code>inovatech-submit</code> para gerar o comprovante e anote o hash.</li>",
    "</ol>",
    '<p class="briefing-note"><strong>Não copie</strong> <code>.venv</code> ou ',
    "<code>node_modules</code> manualmente — eles contêm caminhos absolutos que quebram ",
    "ao mover. Use sempre <code>inovatech-preparar-entrega</code>.</p>",
    '<p class="briefing-note">Critérios de avaliação (200 pts cada): backend, frontend, ',
    "requisitos de negócio, qualidade de código e README com arquitetura e ",
    "instruções de execução (Nota Técnica 02/2026).</p>",
    "</article>",
  ];
  return lines.join("");
}

function headerHtml(): string {
  const parts = [
    '<header class="header">',
    '<div class="brand-row">',
    '<img class="logo-ifpi" src="/logo-inovatech.png"',
    ' alt="Programa Residência em Inovação Tecnológica GAB IFPI" />',
    '<img class="logo-copa" src="/logo-copa-inovatech-preto.png"',
    ' alt="Copa do Mundo InovaTech 2026 — identidade fictícia" />',
    "</div>",
    '<p class="exam-meta">',
    "<strong>Prova Prática INOVATECH 2026</strong> · 02 de maio de 2026 · ",
    "Processo Seletivo — Residência em Inovação Tecnológica · ",
    "Edital 30/2026 — GAB/REI/IFPI.",
    "</p>",
    "<h1>Copa do Mundo InovaTech · O Álbum das Lendas</h1>",
    "</header>",
  ];
  return parts.join("");
}

function footerHtml(): string {
  const parts = [
    '<footer class="footer-copa">',
    '<img src="/logo-copa-inovatech.png" ',
    'alt="Copa do Mundo InovaTech — variante para fundo escuro" />',
    '<p class="footer-caption">Logo fictício — variante para fundos escuros.</p>',
    "</footer>",
  ];
  return parts.join("");
}

function render(): void {
  const app = document.getElementById("app")!;
  app.innerHTML =
    headerHtml() +
    briefingHtml() +
    '<section class="lab-section">' +
    '<h2 class="section-title">Ambiente técnico (hello-world pré-configurado)</h2>' +
    "<p class=\"hint\">Abaixo, exemplo mínimo de listagem de <code>/api/items/</code>. " +
    "Troque por sua própria API do Álbum. Suba os backends antes de clicar nos botões.</p>" +
    '<div class="cards">' +
    backends.map(cardHTML).join("") +
    "</div>" +
    "</section>" +
    footerHtml();

  document.querySelectorAll<HTMLButtonElement>(".btn-fetch").forEach((btn) => {
    btn.addEventListener("click", () => fetchItems(btn));
  });
}

function cardHTML(b: Backend, i: number): string {
  return (
    `
    <div class="card">
      <h2>${b.title}</h2>
      <p class="tech">${b.tech}</p>
      <div class="links">
        API: <a href="${b.api}" target="_blank">${b.api}</a><br/>
        Docs: <a href="${b.docs}" target="_blank">${b.docs}</a>
      </div>
      <button class="btn-fetch" data-url="${b.api}"
              data-idx="${i}">Listar Items</button>
      <div class="result" id="result-${i}"></div>
    </div>
  `
  );
}

async function fetchItems(btn: HTMLButtonElement): Promise<void> {
  const url = btn.dataset.url!;
  const idx = btn.dataset.idx!;
  const el = document.getElementById("result-" + idx)!;

  el.textContent = "Conectando...";
  el.className = "result";

  try {
    const res = await axios.get(url);
    const items = res.data;
    if (items.length === 0) {
      el.textContent = "OK — lista vazia (0 items)";
    } else {
      el.innerHTML = items
        .map((it: { id: number; name: string }) =>
          "<span>#" + it.id + " " + it.name + "</span>"
        )
        .join(", ");
    }
    el.classList.add("ok");
  } catch {
    el.textContent = "Sem resposta — backend offline?";
    el.classList.add("err");
  }
}

render();
MAIN_TS

  # Remove artefatos do template padrão do Vite
  rm -f src/counter.ts src/typescript.svg public/vite.svg 2>/dev/null || true

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

  # ── Branding INOVATECH ──────────────────────────────────────────────────
  cp "${BASE_DIR}/logo-inovatech.png" public/logo-inovatech.png
  # Logos «Copa do Mundo InovaTech 2026» (opcionais junto ao setup no mesmo dir)
  for COPA in logo-copa-inovatech.png logo-copa-inovatech-preto.png; do
    if [[ -f "${BASE_DIR}/${COPA}" ]]; then
      cp "${BASE_DIR}/${COPA}" "public/${COPA}"
    else
      warn "Opcional: ${COPA} não encontrado — coloque-o em ${BASE_DIR}" \
        " para os logos aparecerem na página inicial dos frontends."
    fi
  done

  # ── Pasta de imagens de figurinhas (prova prática) ─────────────────────
  mkdir -p public/assets/figurinhas
  if [ -d "${BASE_DIR}/figurinhas" ]; then
    cp -r "${BASE_DIR}/figurinhas/"* public/assets/figurinhas/ 2>/dev/null || true
  fi

  cat > index.html << 'HTML'
<!DOCTYPE html>
<html lang="pt-BR">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <link rel="icon" type="image/png" href="/logo-inovatech.png" />
    <title>INOVATECH · InovaCup 2026</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
HTML

  cat > src/App.css << 'APPCSS'
:root {
  --navy: #1b2a4a;
  --navy-light: #2d4373;
  --gray-bg: #eef2f7;
  --white: #ffffff;
  --text: #333333;
  --text-muted: #6b7280;
  --green: #16a34a;
  --red: #dc2626;
  --radius: 12px;
}

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family:
    "Segoe UI",
    system-ui,
    -apple-system,
    sans-serif;
  background: linear-gradient(180deg, var(--gray-bg) 0%, #e8ecf4 100%);
  color: var(--text);
  min-height: 100vh;
  padding: 2rem 1rem;
}

.container {
  max-width: 880px;
  width: 100%;
  margin: 0 auto;
}

.header {
  text-align: center;
  margin-bottom: 1.5rem;
}

.brand-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: 1rem 2rem;
  margin-bottom: 0.85rem;
}

.brand-row .logo-ifpi {
  height: 56px;
  width: auto;
}

.brand-row .logo-copa {
  max-height: 76px;
  max-width: min(100%, 360px);
  width: auto;
  height: auto;
  object-fit: contain;
  flex-shrink: 0;
}

.exam-meta {
  font-size: 0.82rem;
  color: var(--text-muted);
  margin-bottom: 0.65rem;
  line-height: 1.5;
}

.header h1 {
  font-size: 1.2rem;
  color: var(--navy);
  font-weight: 700;
  letter-spacing: 0.02em;
  margin-top: 0.25rem;
}

.briefing {
  background: var(--white);
  border-radius: var(--radius);
  padding: 1.25rem 1.45rem;
  margin-bottom: 2rem;
  box-shadow:
    0 1px 3px rgba(0, 0, 0, 0.08),
    0 4px 14px rgba(27, 42, 74, 0.06);
  border: 1px solid rgba(27, 42, 74, 0.08);
}

.briefing h2 {
  font-size: 0.98rem;
  color: var(--navy);
  margin: 1.35rem 0 0.5rem;
  padding-bottom: 0.35rem;
  border-bottom: 1px solid #e5e7eb;
}

.briefing h2:first-child {
  margin-top: 0;
}

.briefing p,
.briefing li {
  font-size: 0.89rem;
  line-height: 1.56;
}

.briefing ul,
.briefing ol {
  padding-left: 1.35rem;
  margin: 0.45rem 0 0.35rem;
}

.briefing-note {
  font-size: 0.82rem;
  color: var(--text-muted);
  padding: 0.65rem 0.85rem;
  background: var(--gray-bg);
  border-radius: 8px;
  margin-top: 0.85rem;
  border-left: 3px solid var(--navy-light);
}

.lab-section {
  margin-top: 0.5rem;
}

.section-title {
  font-size: 1rem;
  color: var(--navy);
  font-weight: 700;
  margin-bottom: 0.65rem;
}

.lab-section .hint {
  font-size: 0.82rem;
  color: var(--text-muted);
  margin-bottom: 1rem;
  line-height: 1.5;
}

.cards {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 1.25rem;
}

.card {
  background: var(--white);
  border-radius: var(--radius);
  padding: 1.5rem;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
  transition:
    box-shadow 0.2s,
    transform 0.2s;
}

.card:hover {
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.12);
  transform: translateY(-2px);
}

.card h2 {
  font-size: 1rem;
  color: var(--navy);
  margin-bottom: 0.25rem;
}

.card .tech {
  font-size: 0.8rem;
  color: var(--text-muted);
  margin-bottom: 0.75rem;
}

.card .links {
  font-size: 0.78rem;
  background: var(--gray-bg);
  padding: 0.5rem 0.75rem;
  border-radius: 6px;
  color: var(--navy-light);
  margin-bottom: 0.75rem;
  word-break: break-all;
}

.card .links a {
  color: var(--navy-light);
}

.btn-fetch {
  display: inline-block;
  padding: 0.4rem 1rem;
  font-size: 0.8rem;
  border: 1px solid var(--navy);
  border-radius: 6px;
  background: var(--white);
  color: var(--navy);
  cursor: pointer;
  transition: background 0.15s;
}

.btn-fetch:hover {
  background: var(--navy);
  color: var(--white);
}

.result {
  margin-top: 0.5rem;
  font-size: 0.78rem;
  min-height: 1.2em;
}

.result.ok {
  color: var(--green);
}

.result.err {
  color: var(--red);
}

.briefing code,
.lab-section code {
  font-size: 0.85em;
  background: #f1f5f9;
  padding: 0.1em 0.35em;
  border-radius: 4px;
}

kbd {
  font-family: ui-monospace, monospace;
  font-size: 0.85em;
  background: #f1f5f9;
  padding: 0.15em 0.4em;
  border-radius: 4px;
  border: 1px solid #e2e8f0;
}

.footer-copa {
  margin-top: 2rem;
  padding: 1.35rem 1rem;
  background: linear-gradient(135deg, #1b2a4a 0%, #243a66 100%);
  text-align: center;
  border-radius: var(--radius);
}

.footer-copa img {
  max-height: 72px;
  width: auto;
}

.footer-caption {
  font-size: 0.75rem;
  color: rgba(255, 255, 255, 0.65);
  margin-top: 0.65rem;
}
APPCSS

  cat > src/App.tsx << 'APPTSX'
import { useState } from "react";
import axios from "axios";
import "./App.css";

interface Backend {
  title: string;
  tech: string;
  api: string;
  docs: string;
}

interface Item {
  id: number;
  name: string;
}

const backends: Backend[] = [
  {
    title: "Django + DRF",
    tech: "Python 3.12 · Django 5.2 · REST Framework",
    api: "http://localhost:8000/api/items/",
    docs: "http://localhost:8000/api/docs/",
  },
  {
    title: "FastAPI + SQLModel",
    tech: "Python 3.12 · FastAPI · Pydantic v2",
    api: "http://localhost:8000/api/items/",
    docs: "http://localhost:8000/docs",
  },
  {
    title: "Express + TypeORM",
    tech: "Node.js 22 · TypeScript · SQLite",
    api: "http://localhost:3000/api/items",
    docs: "http://localhost:3000/health",
  },
];

function Briefing() {
  return (
    <article className="briefing">
      <h2>O que você vai construir</h2>
      <p>
        O{" "}
        <strong>
          Copa do Mundo InovaTech 2026: O Álbum das Lendas
        </strong>{" "}
        é uma plataforma colaborativa para colecionadores de figurinhas de
        jogadores lendários (contexto oficial da sua prova prática).
      </p>
      <p>
        Aplicação em <strong>API RESTful</strong> (backend) e{" "}
        <strong>interface web funcional</strong> (frontend), integradas, usando{" "}
        <strong>SQLite</strong> nas versões fixadas (Notas Técnicas 03, 04 e 05).
      </p>
      <h2>2. Requisitos previstos no edital</h2>
      <p>
        <strong>2.1 Autenticação e perfil:</strong> cadastro (nome, e-mail,
        senha), login com token (JWT diferencial); rota autenticada{" "}
        <code>/me</code>.
      </p>
      <p>
        <strong>2.2 Álbum:</strong> figurinhas com nome do jogador, bio,
        posição, tags de raridade e imagem; cofre para ocultar da listagem
        pública sem excluir; visitantes só veem nomes, sem detalhes.
      </p>
      <p>
        <strong>2.3 Votação:</strong> um voto por figurinha (+1 Craque ou −1
        Bagre); totais e saldo; destaque visual verde ou vermelho no card.
      </p>
      <p>
        <strong>2.4 Interação:</strong> comentários e likes com toggle
        (desfazer).
      </p>
      <h2>O que não entra nestes 3 h</h2>
      <ul>
        <li>Recuperação de senha por e-mail ou serviços externos.</li>
        <li>Editar figurinha depois de publicada (imutabilidade).</li>
        <li>Docker ou deploy em nuvem — entrega local.</li>
      </ul>
      <h2>Como começar a partir deste laboratório</h2>
      <ol>
        <li>
          Este pacote já contém backends e frontends exemplo (hello-world{" "}
          <code>/items</code>), com versões pré-instaladas. Substitua esse
          esqueleto pela sua solução do Álbum.
        </li>
        <li>
          Use <kbd>python3.12</kbd> nos projetos Python; ative cada{" "}
          <code>.venv</code>; em Node <code>nvm use</code> segundo o pacote
          gerado pelo setup.
        </li>
        <li>
          Rode seus servidores (um backend + seu front) e teste o fluxo ponta a
          ponta.
        </li>
        <li>
          Figurinhas estáticas: neste lab coloque arquivos em{" "}
          <code>public/assets/figurinhas/</code> e referencie como{" "}
          <code>/assets/figurinhas/nome.ext</code> (o edital pode citar{" "}
          <code>/assets/cards/</code> — ajuste o caminho se a banca exigir
          exatamente essa pasta).
        </li>
        <li>
          No terminal, rode <code>inovatech-preparar-entrega</code>: ele copia
          seu backend e frontend para <code>entrega_##</code> e recria{" "}
          <code>.venv</code>/<code>node_modules</code> automaticamente.
          Desenvolva a partir daí.
        </li>
        <li>
          Ao terminar, rode <code>inovatech-submit</code> para gerar o
          comprovante e anote o hash.
        </li>
      </ol>
      <p className="briefing-note">
        <strong>Não copie</strong> <code>.venv</code> ou{" "}
        <code>node_modules</code> manualmente — eles contêm caminhos absolutos
        que quebram ao mover. Use sempre{" "}
        <code>inovatech-preparar-entrega</code>.
      </p>
      <p className="briefing-note">
        Critérios de avaliação (200 pts cada): backend, frontend, requisitos de
        negócio, qualidade de código e README com arquitetura e instruções de
        execução (Nota Técnica 02/2026).
      </p>
    </article>
  );
}

function BackendCard({ b }: { b: Backend }) {
  const [result, setResult] = useState("");
  const [cls, setCls] = useState("");

  async function fetchItems() {
    setResult("Conectando...");
    setCls("");
    try {
      const res = await axios.get<Item[]>(b.api);
      const items = res.data;
      if (items.length === 0) {
        setResult("OK — lista vazia (0 items)");
      } else {
        setResult(items.map((it) => `#${it.id} ${it.name}`).join(", "));
      }
      setCls("ok");
    } catch {
      setResult("Sem resposta — backend offline?");
      setCls("err");
    }
  }

  return (
    <div className="card">
      <h2>{b.title}</h2>
      <p className="tech">{b.tech}</p>
      <div className="links">
        API:{" "}
        <a href={b.api} target="_blank" rel="noreferrer">
          {b.api}
        </a>
        <br />
        Docs:{" "}
        <a href={b.docs} target="_blank" rel="noreferrer">
          {b.docs}
        </a>
      </div>
      <button type="button" className="btn-fetch" onClick={fetchItems}>
        Listar Items
      </button>
      <p className={`result ${cls}`}>{result}</p>
    </div>
  );
}

export default function App() {
  return (
    <div className="container">
      <header className="header">
        <div className="brand-row">
          <img
            className="logo-ifpi"
            src="/logo-inovatech.png"
            alt="Programa Residência em Inovação Tecnológica GAB IFPI"
          />
          <img
            className="logo-copa"
            src="/logo-copa-inovatech-preto.png"
            alt="Copa do Mundo InovaTech 2026 — identidade fictícia"
          />
        </div>
        <p className="exam-meta">
          <strong>Prova Prática INOVATECH 2026</strong> · 02 de maio de 2026 ·
          Processo Seletivo — Residência em Inovação Tecnológica · Edital 30/2026
          — GAB/REI/IFPI.
        </p>
        <h1>Copa do Mundo InovaTech · O Álbum das Lendas</h1>
      </header>
      <Briefing />
      <section className="lab-section">
        <h2 className="section-title">
          Ambiente técnico (hello-world pré-configurado)
        </h2>
        <p className="hint">
          Abaixo, exemplo mínimo de listagem de <code>/api/items/</code>. Troque
          por sua própria API do Álbum. Suba os backends antes de clicar nos
          botões.
        </p>
        <div className="cards">
          {backends.map((b) => (
            <BackendCard key={b.title} b={b} />
          ))}
        </div>
      </section>
      <footer className="footer-copa">
        <img
          src="/logo-copa-inovatech.png"
          alt="Copa do Mundo InovaTech — variante para fundo escuro"
        />
        <p className="footer-caption">
          Logo fictício — variante para fundos escuros.
        </p>
      </footer>
    </div>
  );
}
APPTSX

  # Remove artefatos do template padrão do Vite
  rm -f src/assets/react.svg public/vite.svg 2>/dev/null || true

  # ── main.tsx com BrowserRouter pré-configurado ─────────────────────────
  cat > src/main.tsx << 'MAINTSX'
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import App from "./App";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </StrictMode>
);
MAINTSX

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

sha256() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

inovatech_ascii_banner() {
  echo -e "${BOLD}${CYAN}"
  cat << 'INVASCII'
██╗███╗   ██╗ ██████╗ ██╗   ██╗ █████╗ ████████╗███████╗ ██████╗██╗  ██╗
██║████╗  ██║██╔═══██╗██║   ██║██╔══██╗╚══██╔══╝██╔════╝██╔════╝██║  ██║
██║██╔██╗ ██║██║   ██║██║   ██║███████║   ██║   █████╗  ██║     ███████║
██║██║╚██╗██║██║   ██║╚██╗ ██╔╝██╔══██║   ██║   ██╔══╝  ██║     ██╔══██║
██║██║ ╚████║╚██████╔╝ ╚████╔╝ ██║  ██║   ██║   ███████╗╚██████╗██║  ██║
╚═╝╚═╝  ╚═══╝ ╚═════╝   ╚═══╝  ╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚═════╝╚═╝  ╚═╝
INVASCII
  echo -e "${RESET}"
}

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

echo ""
inovatech_ascii_banner
echo ""
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
    ! -name "*.sqlite3" \
    ! -name "*.db" \
    ! -name "package-lock.json" \
    | LC_ALL=C sort
}

MANIFEST_FILE="${COMPROVANTE_DIR}/manifesto_entrega_${DATESTAMP}.txt"
COMPROVANTE_FILE="${COMPROVANTE_DIR}/comprovante_PP_${CODIGO_PP}_${DATESTAMP}.txt"

info "Calculando hashes dos arquivos entregues..."
echo ""

{
  echo "# ============================================="
  echo "# INOVATECH – Manifesto de Entrega"
  echo "# Candidato  : ${CANDIDATO_NOME}"
  echo "# Código PP  : ${CODIGO_PP}"
  echo "# Data/Hora  : ${TIMESTAMP}"
  echo "# Algoritmo  : SHA-256"
  echo "# Hash raiz  : SHA-256 da concatenação dos"
  echo "#   hashes individuais em ordem lexicográfica"
  echo "# ============================================="
  echo ""
} > "${MANIFEST_FILE}"

HASH_ENTRIES_FILE=$(mktemp)
trap 'rm -f "${HASH_ENTRIES_FILE}"' EXIT
FILE_COUNT=0

while IFS= read -r filepath; do
  rel="${filepath#${ENTREGA_DIR}/}"
  file_hash=$(sha256 "${filepath}" | awk '{print $1}')
  printf "%-64s  %s\n" \
    "${file_hash}" "${rel}" >> "${MANIFEST_FILE}"
  printf '%s\n' "${file_hash}" >> "${HASH_ENTRIES_FILE}"
  FILE_COUNT=$((FILE_COUNT + 1))
done < <(list_files "${ENTREGA_DIR}")

ENTREGA_HASH=$(
  LC_ALL=C sort "${HASH_ENTRIES_FILE}" \
    | sha256 | awk '{print $1}'
)

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
# 10b. Embutir script inovatech-enviar-entrega (comissão, pós-prova / API HTTPS)
# ---------------------------------------------------------------------------
header "Instalando comando inovatech-enviar-entrega"

ENVIAR_BIN="/usr/local/bin/inovatech-enviar-entrega"

cat > /tmp/inovatech-enviar-entrega << 'ENVIAR_SCRIPT'
#!/usr/bin/env bash
# =============================================================================
# INOVATECH – Enviar entrega por HTTPS (multipart) — COMISSÃO, pós-prova
#
# Modalidade laboratório: nome_candidato + codigo_posicao (+ edicao_pk se
# necessário). Modalidade token: --token (Bearer). Ver ENTREGA-PROVA-PRATICA-API.
#
# Config opcional: /etc/inovatech/entrega.env (export INOVATECH_*)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${RESET} $*"; }
error()   { echo -e "${RED}[ERRO]${RESET}  $*"; exit 1; }

if [[ -r /etc/inovatech/entrega.env ]]; then
  # shellcheck source=/dev/null
  source /etc/inovatech/entrega.env
fi

DEFAULT_URL="https://inovatech.ifpi.edu.br/api/entrega-prova-pratica/"
MAX_BYTES=$((80 * 1024 * 1024))

ENTREGA_DIR=""
URL="${INOVATECH_ENTREGA_URL:-$DEFAULT_URL}"
SECRET="${INOVATECH_ENTREGA_SECRET:-}"
EDICAO_PK="${INOVATECH_EDICAO_PK:-}"
NOME=""
CODIGO=""
TOKEN=""
SEM_COMPROVANTE=0
FORCE=0
INV_ROOT="${INOVATECH_ROOT:-${HOME}/inovatech}"

usage() {
  sed -n '1,80p' << 'USAGE'
Uso: inovatech-enviar-entrega [opções]

  Comissão: após liberar a internet, envia a pasta de entrega (ZIP) à API.

Modo laboratório (padrão):
  --nome "nome do candidato"
  --codigo N   (posição na classificação geral, 01–40 típ.)
  --edicao-pk N   (se o servidor não tiver PROVA_PRATICA_ENTREGA_EDICAO_PK)

Modo token:
  --token BEARER   (não usa --nome / --codigo)

Geral:
  --dir /caminho/entrega_##   (senão: deteta em $INOVATECH_ROOT ou ~/inovatech)
  --url URL          (padrão: produção inovatech.ifpi.edu.br)
  --secret VALOR     → cabeçalho X-Entrega-Prova-Pratica-Secret
  --sem-comprovante  exclui .comprovante/ do ZIP (alinha ao manifesto hasheado)
  --force            envia mesmo se ZIP > 80 MiB

Variáveis de ambiente: INOVATECH_ENTREGA_URL, INOVATECH_ENTREGA_SECRET,
  INOVATECH_EDICAO_PK, INOVATECH_ROOT

Arquivo opcional: /etc/inovatech/entrega.env
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)            ENTREGA_DIR="$2"; shift 2 ;;
    --url)            URL="$2"; shift 2 ;;
    --secret)         SECRET="$2"; shift 2 ;;
    --edicao-pk)      EDICAO_PK="$2"; shift 2 ;;
    --nome)           NOME="$2"; shift 2 ;;
    --codigo)         CODIGO="$2"; shift 2 ;;
    --token)          TOKEN="$2"; shift 2 ;;
    --sem-comprovante) SEM_COMPROVANTE=1; shift ;;
    --force)          FORCE=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) error "Opção desconhecida: $1 (use --help)" ;;
  esac
done

command -v curl &>/dev/null || error "curl não encontrado."
command -v zip &>/dev/null || error "Comando 'zip' não encontrado. Instale: sudo apt install zip"

# ---- Detetar pasta de entrega (igual inovatech-submit, base INOVATECH_ROOT) ----
if [[ -z "${ENTREGA_DIR}" ]]; then
  cands=()
  if [[ -d "${INV_ROOT}/entrega" ]]; then
    cands+=("${INV_ROOT}/entrega")
  fi
  shopt -s nullglob
  for d in "${INV_ROOT}"/entrega_[0-9][0-9]; do
    [[ -d "$d" ]] || continue
    bname=$(basename "$d")
    code=${bname#entrega_}
    if [[ "${code}" =~ ^(0[1-9]|[1-3][0-9]|40)$ ]]; then
      cands+=("$d")
    fi
  done
  shopt -u nullglob
  nc=${#cands[@]}
  if [[ "${nc}" -eq 0 ]]; then
    error "Pasta de entrega não encontrada em ${INV_ROOT}. Use" \
          " --dir /caminho ou defina/há entrega_##"
  elif [[ "${nc}" -gt 1 ]]; then
    error "Várias pastas de entrega em ${INV_ROOT}. Especifique:" \
          " inovatech-enviar-entrega --dir /caminho"
  else
    ENTREGA_DIR="${cands[0]}"
  fi
fi

[[ -d "${ENTREGA_DIR}" ]] || error "Pasta não encontrada: ${ENTREGA_DIR}"
ENTREGA_ABS="$(cd "${ENTREGA_DIR}" && pwd)"

# ---- Modo token vs laboratório + prompts se faltar ----
LAB=1
if [[ -n "${TOKEN}" ]]; then
  LAB=0
elif [[ -z "${NOME}" || -z "${CODIGO}" ]]; then
  echo -e "${BOLD}Identificação (modo laboratório)${RESET}"
  [[ -z "${NOME}" ]] && read -rp "  nome_candidato: " NOME
  [[ -z "${CODIGO}" ]] && read -rp "  codigo_posicao (01–40 típ.): " CODIGO
fi

if [[ "${LAB}" -eq 1 ]]; then
  [[ -n "${NOME// }" ]] || error "nome_candidato é obrigatório."
  [[ -n "${CODIGO// }" ]] || error "codigo_posicao é obrigatório."
  # Normalização leve para nome do arquivo
  CODIGO_TR=$(echo "${CODIGO}" | xargs)
  if [[ "${CODIGO_TR}" =~ ^[0-9]+$ ]]; then
    CODZIP=$(printf '%02d' "$((10#${CODIGO_TR}))")
  else
    CODZIP="XX"
  fi
else
  CODZIP=""
fi

DATESTAMP=$(date '+%Y%m%d_%H%M%S')
TMPZIP="$(mktemp /tmp/inovatech_entrega_XXXXXX.zip)"
BODY="$(mktemp)"
trap 'rm -f "${TMPZIP}" "${BODY}" 2>/dev/null' EXIT

echo ""
echo -e "${BOLD}${CYAN}INOVATECH – Envio HTTPS (comissão – pós-prova)${RESET}"
echo ""

info "Empacotando: ${ENTREGA_ABS}"

build_zip() {
  if [[ "${SEM_COMPROVANTE}" -eq 1 ]]; then
    (
      cd "${ENTREGA_ABS}" || exit 1
      find . -type f \
        ! -path '*/.venv/*' \
        ! -path '*/node_modules/*' \
        ! -path '*/__pycache__/*' \
        ! -path '*/.git/*' \
        ! -name '*.pyc' \
        ! -name '*.pyo' \
        ! -path '*/dist/*' \
        ! -path '*/.comprovante/*' \
        ! -name '*.log' \
        ! -name '.DS_Store' \
        ! -name '*.sqlite3' \
        ! -name '*.db' \
        ! -name 'package-lock.json' \
        | LC_ALL=C sort \
        | zip -q "${TMPZIP}" -@
    )
  else
    (
      cd "${ENTREGA_ABS}" || exit 1
      find . -type f \
        ! -path '*/.venv/*' \
        ! -path '*/node_modules/*' \
        ! -path '*/__pycache__/*' \
        ! -path '*/.git/*' \
        ! -name '*.pyc' \
        ! -name '*.pyo' \
        ! -path '*/dist/*' \
        ! -name '*.log' \
        ! -name '.DS_Store' \
        ! -name '*.sqlite3' \
        ! -name '*.db' \
        ! -name 'package-lock.json' \
        | LC_ALL=C sort \
        | zip -q "${TMPZIP}" -@
    )
  fi
}

build_zip

ZS=$(stat -c%s "${TMPZIP}" 2>/dev/null || stat -f%z "${TMPZIP}" 2>/dev/null || echo 0)
if [[ "${ZS}" -eq 0 ]]; then
  error "ZIP vazio — nenhum ficheiro após filtros?"
fi

if [[ "${ZS}" -gt "${MAX_BYTES}" ]] && [[ "${FORCE}" -eq 0 ]]; then
  error "ZIP com ${ZS} bytes excede 80 MiB. Reduza a pasta ou use --force" \
        " (ou confirme Nginx/backend)."
fi
if [[ "${ZS}" -gt "${MAX_BYTES}" ]]; then
  warn "ZIP > 80 MiB — envio pode falhar com 413."
fi

read_sig=$(head -c 2 "${TMPZIP}" || true)
if [[ "${read_sig}" != $'PK' ]]; then
  error "Ficheiro gerado não parece ZIP (assinatura PK ausente)."
fi

ZIPNAME="inovatech_entrega_${CODZIP:-na}_${DATESTAMP}.zip"
info "ZIP: ${ZS} bytes → ${ZIPNAME}"

if [[ "${LAB}" -eq 1 ]]; then
  NOME="$(echo "${NOME}" | xargs)"
  CODIGO="$(echo "${CODIGO}" | xargs)"
fi

# ---- CURL ----
HEADER_ARGS=()
if [[ -n "${SECRET}" ]]; then
  HEADER_ARGS+=( -H "X-Entrega-Prova-Pratica-Secret: ${SECRET}" )
fi

MULTI=( -sS \
  --max-time 600 \
  --retry 3 \
  --retry-all-errors )

if [[ "${LAB}" -eq 1 ]]; then
  MULTI+=(
    -F "nome_candidato=${NOME}"
    -F "codigo_posicao=${CODIGO}"
    -F "arquivo=@${TMPZIP};filename=${ZIPNAME};type=application/zip"
  )
  [[ -n "${EDICAO_PK}" ]] && MULTI+=( -F "edicao_pk=${EDICAO_PK}" )
else
  MULTI+=(
    -H "Authorization: Bearer ${TOKEN}"
    -F "arquivo=@${TMPZIP};filename=${ZIPNAME};type=application/zip"
  )
fi

HTTP=$(curl "${MULTI[@]}" "${HEADER_ARGS[@]}" -o "${BODY}" \
  -w '%{http_code}' "${URL}")

echo ""
echo -e "${BOLD}Resposta HTTP: ${HTTP}${RESET}"
cat "${BODY}"
echo ""

if [[ "${HTTP}" != "200" ]]; then
  error "Upload falhou (HTTP ${HTTP}). Ver JSON acima."
fi

OK=0
if command -v jq &>/dev/null; then
  jq -e '.ok == true' "${BODY}" &>/dev/null && OK=1 || true
else
  if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('ok') is True else 1)" "${BODY}" 2>/dev/null; then OK=1; fi
fi
if [[ "${OK}" -eq 1 ]]; then
  success "Entrega registada pela API."
else
  error "HTTP 200 mas campo ok não é true — conferir JSON acima."
fi
ENVIAR_SCRIPT

if [ "$(id -u)" -eq 0 ]; then
  cp /tmp/inovatech-enviar-entrega "${ENVIAR_BIN}"
  chmod +x "${ENVIAR_BIN}"
  success "Comando instalado: ${ENVIAR_BIN}"
else
  warn "Setup não está rodando como root — tentando sudo para inovatech-enviar-entrega..."
  sudo cp /tmp/inovatech-enviar-entrega "${ENVIAR_BIN}" \
    && sudo chmod +x "${ENVIAR_BIN}" \
    && success "Comando instalado: ${ENVIAR_BIN}" \
    || warn "Não foi possível instalar inovatech-enviar-entrega em /usr/local/bin."
fi
rm -f /tmp/inovatech-enviar-entrega 2>/dev/null || true

# ---------------------------------------------------------------------------
# 11. Embutir script inovatech-preparar-entrega
# ---------------------------------------------------------------------------
header "Instalando comando inovatech-preparar-entrega"

PREP_BIN="/usr/local/bin/inovatech-preparar-entrega"

cat > /tmp/inovatech-preparar-entrega << 'PREP_SCRIPT'
#!/usr/bin/env bash
# =============================================================================
# INOVATECH – Preparar pasta de entrega
#
# Copia o backend e o frontend escolhidos pelo candidato para entrega_##,
# recria .venv (Python) e node_modules (Node) para que tudo funcione
# no novo caminho.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${RESET} $*"; }
error()   { echo -e "${RED}[ERRO]${RESET}  $*"; exit 1; }

INV_ROOT="${HOME}/inovatech"
[ -d "${INV_ROOT}" ] \
  || error "Diretório ${INV_ROOT} não encontrado."

echo ""
echo -e "${BOLD}${CYAN}======================================${RESET}"
echo -e "${BOLD}${CYAN}  INOVATECH – Preparar Entrega${RESET}"
echo -e "${BOLD}${CYAN}======================================${RESET}"
echo ""

# ── Código do candidato ──────────────────────────────────────────────────
read -rp "  Seu código PP (01 a 40): " CODIGO_PP
CODIGO_PP=$(echo "${CODIGO_PP}" | xargs)
[[ "${CODIGO_PP}" =~ ^[0-9]{1,2}$ ]] \
  || error "Código PP inválido. Use um número de 01 a 40."
CODIGO_PP=$(printf "%02d" "${CODIGO_PP}")

ENTREGA_DIR="${INV_ROOT}/entrega_${CODIGO_PP}"

if [ -d "${ENTREGA_DIR}" ]; then
  warn "Pasta ${ENTREGA_DIR} já existe."
  read -rp "  Deseja continuar e sobrescrever? (s/N): " CONFIRM
  [[ "${CONFIRM}" =~ ^[sS]$ ]] || { info "Cancelado."; exit 0; }
fi

mkdir -p "${ENTREGA_DIR}"

# ── Backend ──────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Qual backend você está usando?${RESET}"
echo "  1) Django + DRF        (backend-django)"
echo "  2) FastAPI + SQLModel   (backend-fastapi)"
echo "  3) Express + TypeORM    (backend-express)"
read -rp "  Opção (1/2/3): " BACK_OPT

case "${BACK_OPT}" in
  1) BACK_NAME="backend-django"  ;;
  2) BACK_NAME="backend-fastapi" ;;
  3) BACK_NAME="backend-express" ;;
  *) error "Opção inválida." ;;
esac

BACK_SRC="${INV_ROOT}/${BACK_NAME}"
[ -d "${BACK_SRC}" ] \
  || error "Pasta ${BACK_SRC} não encontrada."

# ── Frontend ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Qual frontend você está usando?${RESET}"
echo "  1) React + TypeScript   (frontend-react)"
echo "  2) Vanilla + TypeScript (frontend-vanilla)"
read -rp "  Opção (1/2): " FRONT_OPT

case "${FRONT_OPT}" in
  1) FRONT_NAME="frontend-react"   ;;
  2) FRONT_NAME="frontend-vanilla" ;;
  *) error "Opção inválida." ;;
esac

FRONT_SRC="${INV_ROOT}/${FRONT_NAME}"
[ -d "${FRONT_SRC}" ] \
  || error "Pasta ${FRONT_SRC} não encontrada."

# ── Copiar backend (sem .venv, __pycache__, *.db, *.sqlite3) ────────────
echo ""
info "Copiando ${BACK_NAME} → ${ENTREGA_DIR}/${BACK_NAME}/"
rsync -a --delete \
  --exclude '.venv' \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  --exclude '*.pyo' \
  --exclude '*.sqlite3' \
  --exclude '*.db' \
  --exclude 'node_modules' \
  --exclude '.DS_Store' \
  "${BACK_SRC}/" "${ENTREGA_DIR}/${BACK_NAME}/"

# ── Copiar frontend (sem node_modules, dist) ────────────────────────────
info "Copiando ${FRONT_NAME} → ${ENTREGA_DIR}/${FRONT_NAME}/"
rsync -a --delete \
  --exclude 'node_modules' \
  --exclude 'dist' \
  --exclude '.DS_Store' \
  "${FRONT_SRC}/" "${ENTREGA_DIR}/${FRONT_NAME}/"

# ── Logos / figurinhas na raiz do laboratório (mesmo fluxo do setup) ────
# O rsync espelha só o frontend; PNGs da Copa costumam estar em ~/inovatech/
# e podem faltar em public/ se não forem versionados — o --delete então remove
# cópias antigas na entrega. Recolocamos a partir da raiz para não quebrar a UI.
DEST_FRONT="${ENTREGA_DIR}/${FRONT_NAME}"
mkdir -p "${DEST_FRONT}/public"
info "Sincronizando logos INOVATECH em ${DEST_FRONT}/public/ ..."
for brand in logo-inovatech.png logo-copa-inovatech.png logo-copa-inovatech-preto.png; do
  if [[ -f "${INV_ROOT}/${brand}" ]]; then
    cp "${INV_ROOT}/${brand}" "${DEST_FRONT}/public/${brand}"
  fi
done
if [[ -d "${INV_ROOT}/figurinhas" ]]; then
  mkdir -p "${DEST_FRONT}/public/assets/figurinhas"
  cp -r "${INV_ROOT}/figurinhas/"* "${DEST_FRONT}/public/assets/figurinhas/" 2>/dev/null \
    || true
fi

# ── Recriar .venv do backend Python ─────────────────────────────────────
DEST_BACK="${ENTREGA_DIR}/${BACK_NAME}"

if [[ "${BACK_NAME}" == backend-django || "${BACK_NAME}" == backend-fastapi ]]; then
  info "Recriando .venv em ${DEST_BACK}/ ..."

  PYTHON312=""
  for p in python3.12 python3; do
    if command -v "$p" &>/dev/null; then
      PYTHON312="$p"; break
    fi
  done
  [ -n "${PYTHON312}" ] || error "Python 3.12 não encontrado no PATH."

  UV=""
  if command -v uv &>/dev/null; then
    UV=$(command -v uv)
  fi

  if [ -n "${UV}" ]; then
    "${UV}" venv "${DEST_BACK}/.venv" --python "${PYTHON312}" --quiet

    if [ -f "${BACK_SRC}/requirements.txt" ]; then
      "${UV}" pip install \
        --python "${DEST_BACK}/.venv/bin/python" \
        -r "${BACK_SRC}/requirements.txt" --quiet
    else
      OLD_REQS=$("${UV}" pip freeze \
        --python "${BACK_SRC}/.venv/bin/python" 2>/dev/null || true)
      if [ -n "${OLD_REQS}" ]; then
        echo "${OLD_REQS}" | "${UV}" pip install \
          --python "${DEST_BACK}/.venv/bin/python" \
          -r /dev/stdin --quiet
      elif [[ "${BACK_NAME}" == "backend-fastapi" ]]; then
        warn "Sem requirements.txt no projeto-base — instalando pinagens oficiais INOVATECH (FastAPI)."
        "${UV}" pip install --python "${DEST_BACK}/.venv/bin/python" \
          "fastapi==0.136.0" "uvicorn==0.45.0" "starlette==1.0.0" \
          "sqlmodel==0.0.38" "alembic==1.18.4" "SQLAlchemy==2.0.49" \
          "Mako==1.3.11" "pyjwt==2.9.0" "python-jose[cryptography]==3.5.0" \
          "passlib==1.7.4" "bcrypt==3.2.2" "python-multipart==0.0.26" \
          "email-validator==2.3.0" "httpx==0.28.1" "anyio==4.13.0" \
          "pydantic==2.13.3" "pydantic-settings==2.14.0" \
          "annotated-types==0.7.0" --quiet
      else
        warn "Sem requirements.txt e sem .venv original — .venv vazio."
        warn "Instale os pacotes manualmente: cd ${DEST_BACK} && source .venv/bin/activate && pip install ..."
      fi
    fi
    success ".venv recriado com $(${DEST_BACK}/.venv/bin/python --version)"
  else
    warn "uv não encontrado — criando .venv com venv padrão..."
    "${PYTHON312}" -m venv "${DEST_BACK}/.venv"

    if [ -f "${BACK_SRC}/requirements.txt" ]; then
      "${DEST_BACK}/.venv/bin/pip" install -q \
        -r "${BACK_SRC}/requirements.txt"
    else
      OLD_REQS=$("${BACK_SRC}/.venv/bin/pip" freeze 2>/dev/null || true)
      if [ -n "${OLD_REQS}" ]; then
        echo "${OLD_REQS}" | "${DEST_BACK}/.venv/bin/pip" install -q \
          -r /dev/stdin
      elif [[ "${BACK_NAME}" == "backend-fastapi" ]]; then
        warn "Sem requirements.txt no projeto-base — instalando pinagens oficiais INOVATECH (FastAPI)."
        "${DEST_BACK}/.venv/bin/pip" install -q \
          "fastapi==0.136.0" "uvicorn==0.45.0" "starlette==1.0.0" \
          "sqlmodel==0.0.38" "alembic==1.18.4" "SQLAlchemy==2.0.49" \
          "Mako==1.3.11" "pyjwt==2.9.0" "python-jose[cryptography]==3.5.0" \
          "passlib==1.7.4" "bcrypt==3.2.2" "python-multipart==0.0.26" \
          "email-validator==2.3.0" "httpx==0.28.1" "anyio==4.13.0" \
          "pydantic==2.13.3" "pydantic-settings==2.14.0" \
          "annotated-types==0.7.0"
      fi
    fi
    success ".venv recriado (sem uv, pode ter sido mais lento)."
  fi
fi

# ── Recriar node_modules do frontend ────────────────────────────────────
info "Instalando dependências em ${DEST_FRONT}/ ..."
cd "${DEST_FRONT}"

export NVM_DIR="${HOME}/.nvm"
# shellcheck disable=SC1091
[ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"
nvm use 2>/dev/null || true

npm install --quiet 2>/dev/null
success "node_modules instalado."

# ── Recriar node_modules do backend Express (se for o caso) ─────────────
if [[ "${BACK_NAME}" == "backend-express" ]]; then
  info "Instalando dependências do Express em ${DEST_BACK}/ ..."
  cd "${DEST_BACK}"
  npm install --quiet 2>/dev/null
  success "node_modules do Express instalado."
fi

# ── Resumo ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}======================================${RESET}"
echo -e "${BOLD}${GREEN}  Entrega preparada com sucesso!${RESET}"
echo -e "${BOLD}${GREEN}======================================${RESET}"
echo ""
echo -e "  Pasta   : ${BOLD}${ENTREGA_DIR}${RESET}"
echo -e "  Backend : ${BOLD}${BACK_NAME}${RESET}"
echo -e "  Frontend: ${BOLD}${FRONT_NAME}${RESET}"
echo ""
echo -e "  Continue desenvolvendo dentro de ${BOLD}${ENTREGA_DIR}${RESET}."
echo -e "  Ao finalizar, rode: ${BOLD}inovatech-submit${RESET}"
echo ""
if [[ "${BACK_NAME}" == "backend-fastapi" ]]; then
  info "Dica: se precisar rodar o backend FastAPI (usa o Python do .venv):"
  echo "    cd ${DEST_BACK} && .venv/bin/python -m uvicorn main:app --reload"
elif [[ "${BACK_NAME}" == "backend-django" ]]; then
  info "Dica: se precisar rodar o backend Django:"
  echo "    cd ${DEST_BACK} && .venv/bin/python manage.py runserver"
elif [[ "${BACK_NAME}" == "backend-express" ]]; then
  info "Dica: se precisar rodar o backend Express:"
  echo "    cd ${DEST_BACK} && npm run dev"
else
  info "Dica: se precisar rodar o backend Python:"
  echo "    cd ${DEST_BACK} && source .venv/bin/activate"
fi
echo ""
info "Dica: se precisar rodar o frontend:"
echo "    cd ${DEST_FRONT} && npm run dev"
echo ""
PREP_SCRIPT

if [ "$(id -u)" -eq 0 ]; then
  cp /tmp/inovatech-preparar-entrega "${PREP_BIN}"
  chmod +x "${PREP_BIN}"
  success "Comando instalado: ${PREP_BIN}"
else
  warn "Setup não está rodando como root — tentando sudo..."
  sudo cp /tmp/inovatech-preparar-entrega "${PREP_BIN}" \
    && sudo chmod +x "${PREP_BIN}" \
    && success "Comando instalado: ${PREP_BIN}" \
    || warn "Não foi possível instalar em /usr/local/bin; use" \
" /tmp/inovatech-preparar-entrega (caminho completo)."
fi

# ---------------------------------------------------------------------------
# 12. Embutir script inovatech-seal
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

sha256() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

inovatech_ascii_banner() {
  echo -e "${BOLD}${CYAN}"
  cat << 'INVASCII'
██╗███╗   ██╗ ██████╗ ██╗   ██╗ █████╗ ████████╗███████╗ ██████╗██╗  ██╗
██║████╗  ██║██╔═══██╗██║   ██║██╔══██╗╚══██╔══╝██╔════╝██╔════╝██║  ██║
██║██╔██╗ ██║██║   ██║██║   ██║███████║   ██║   █████╗  ██║     ███████║
██║██║╚██╗██║██║   ██║╚██╗ ██╔╝██╔══██║   ██║   ██╔══╝  ██║     ██╔══██║
██║██║ ╚████║╚██████╔╝ ╚████╔╝ ██║  ██║   ██║   ███████╗╚██████╗██║  ██║
╚═╝╚═╝  ╚═══╝ ╚═════╝   ╚═══╝  ╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚═════╝╚═╝  ╚═╝
INVASCII
  echo -e "${RESET}"
}

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

echo ""
inovatech_ascii_banner
echo ""
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
    ! -name "*.sqlite3" \
    ! -name "*.db" \
    ! -name "package-lock.json" \
    | LC_ALL=C sort
}

info "Gerando manifesto de hashes por arquivo..."
echo ""

{
  echo "# ============================================="
  echo "# INOVATECH – Manifesto de Integridade"
  echo "# Gerado em  : ${TIMESTAMP}"
  echo "# Algoritmo  : SHA-256"
  echo "# Hash raiz  : SHA-256 da concatenação ordenada de"
  echo "#   caminho_relativo<TAB>hash_arquivo (LC_ALL=C)"
  echo "# ============================================="
  echo ""
} > "${MANIFEST_FILE}"

HASH_ENTRIES_FILE=$(mktemp)
trap 'rm -f "${HASH_ENTRIES_FILE}"' EXIT

for proj in "${PROJECT_DIRS[@]}"; do
  echo "## Projeto: ${proj}" >> "${MANIFEST_FILE}"
  echo "" >> "${MANIFEST_FILE}"
  file_count=0
  while IFS= read -r relpath; do
    file_hash=$(sha256 "${BASE_DIR}/${relpath}" | awk '{print $1}')
    printf "%-64s  %s\n" \
      "${file_hash}" "${relpath}" >> "${MANIFEST_FILE}"
    printf '%s\t%s\n' "${relpath}" "${file_hash}" >> "${HASH_ENTRIES_FILE}"
    file_count=$((file_count + 1))
  done < <( cd "${BASE_DIR}" && list_files "${proj}" )
  echo "" >> "${MANIFEST_FILE}"
  success "  ${proj}/ → ${file_count} arquivos"
done

TOTAL=$(wc -l < "${HASH_ENTRIES_FILE}" | tr -d ' ')
info "Total de arquivos hasheados: ${TOTAL}"

ROOT_HASH=$(
  LC_ALL=C sort "${HASH_ENTRIES_FILE}" \
    | sha256 | awk '{print $1}'
)

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
# 12. inovatech-verify — candidato confere integridade do ambiente
#     Somente leitura: recalcula o hash raiz e exibe para comparação
#     com o hash público divulgado pela coordenação.
# ---------------------------------------------------------------------------
header "Instalando comando inovatech-verify"

VERIFY_BIN="/usr/local/bin/inovatech-verify"

cat > /tmp/inovatech-verify << 'VERIFY_SCRIPT'
#!/usr/bin/env bash
# =============================================================================
# INOVATECH – Verificação de Integridade (somente leitura)
# Uso pelo CANDIDATO ao chegar no computador, antes de iniciar a prova.
# Recalcula o hash raiz dos projetos base e exibe para comparação
# com o hash público divulgado pela coordenação.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${RESET} $*"; }
error()   { echo -e "${RED}[ERRO]${RESET}  $*"; exit 1; }

inovatech_ascii_banner() {
  echo -e "${BOLD}${CYAN}"
  cat << 'INVASCII'
██╗███╗   ██╗ ██████╗ ██╗   ██╗ █████╗ ████████╗███████╗ ██████╗██╗  ██╗
██║████╗  ██║██╔═══██╗██║   ██║██╔══██╗╚══██╔══╝██╔════╝██╔════╝██║  ██║
██║██╔██╗ ██║██║   ██║██║   ██║███████║   ██║   █████╗  ██║     ███████║
██║██║╚██╗██║██║   ██║╚██╗ ██╔╝██╔══██║   ██║   ██╔══╝  ██║     ██╔══██║
██║██║ ╚████║╚██████╔╝ ╚████╔╝ ██║  ██║   ██║   ███████╗╚██████╗██║  ██║
╚═╝╚═╝  ╚═══╝ ╚═════╝   ╚═══╝  ╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚═════╝╚═╝  ╚═╝
INVASCII
  echo -e "${RESET}"
}

sha256() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

BASE_DIR="$(pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) BASE_DIR="$2"; shift 2 ;;
    *) error "Argumento desconhecido: $1" ;;
  esac
done

[ -d "${BASE_DIR}" ] || error "Diretório não encontrado: ${BASE_DIR}"

PROJECT_DIRS=(
  "backend-django"
  "backend-fastapi"
  "backend-express"
  "frontend-vanilla"
  "frontend-react"
)

echo ""
inovatech_ascii_banner
echo ""
echo -e "${BOLD}${CYAN}======================================${RESET}"
echo -e "${BOLD}${CYAN}  INOVATECH – Verificação de Integridade${RESET}"
echo -e "${BOLD}${CYAN}======================================${RESET}"
echo ""
info "Diretório base : ${BASE_DIR}"
info "Data/Hora      : $(date '+%Y-%m-%dT%H:%M:%S')"
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
    ! -name "*.sqlite3" \
    ! -name "*.db" \
    ! -name "package-lock.json" \
    | LC_ALL=C sort
}

info "Calculando hashes (pode levar alguns segundos)..."
echo ""

HASH_ENTRIES_FILE=$(mktemp)
trap 'rm -f "${HASH_ENTRIES_FILE}"' EXIT

for proj in "${PROJECT_DIRS[@]}"; do
  file_count=0
  while IFS= read -r relpath; do
    file_hash=$(sha256 "${BASE_DIR}/${relpath}" | awk '{print $1}')
    printf '%s\t%s\n' "${relpath}" "${file_hash}" >> "${HASH_ENTRIES_FILE}"
    file_count=$((file_count + 1))
  done < <( cd "${BASE_DIR}" && list_files "${proj}" )
  success "  ${proj}/ → ${file_count} arquivos"
done

TOTAL=$(wc -l < "${HASH_ENTRIES_FILE}" | tr -d ' ')
info "Total de arquivos hasheados: ${TOTAL}"

ROOT_HASH=$(
  LC_ALL=C sort "${HASH_ENTRIES_FILE}" \
    | sha256 | awk '{print $1}'
)

echo ""
echo "=============================================================="
echo "  INOVATECH – Resultado da Verificação"
echo "  Edital 30/2026 – GAB/REI/IFPI"
echo "=============================================================="
echo ""
echo "  Algoritmo : SHA-256 (hash raiz)"
echo ""
echo "  HASH CALCULADO NESTE COMPUTADOR"
echo "  ────────────────────────────────────────────────────────────"
echo "  ${ROOT_HASH}"
echo "  ────────────────────────────────────────────────────────────"
echo ""
echo -e "  ${BOLD}Compare o hash acima com o HASH PÚBLICO OFICIAL${RESET}"
echo "  divulgado pela coordenação."
echo ""
echo -e "  Se forem ${GREEN}${BOLD}iguais${RESET}: ambiente íntegro, pode iniciar a prova."
echo -e "  Se forem ${RED}${BOLD}diferentes${RESET}: comunique a coordenação imediatamente."
echo "=============================================================="
echo ""
VERIFY_SCRIPT

if [ "$(id -u)" -eq 0 ]; then
  cp /tmp/inovatech-verify "${VERIFY_BIN}"
  chmod +x "${VERIFY_BIN}"
  success "Comando instalado: ${VERIFY_BIN}"
else
  sudo cp /tmp/inovatech-verify "${VERIFY_BIN}" \
    && sudo chmod +x "${VERIFY_BIN}" \
    && success "Comando instalado: ${VERIFY_BIN}" \
    || warn "Não foi possível instalar inovatech-verify em /usr/local/bin."
fi
rm -f /tmp/inovatech-verify 2>/dev/null || true

# ---------------------------------------------------------------------------
# 13. inovatech-versions — listar versões (candidato verifica o ambiente)
# ---------------------------------------------------------------------------
header "Instalando comando inovatech-versions"

VERSIONS_BIN="/usr/local/bin/inovatech-versions"

cat > /tmp/inovatech-versions << 'VERSIONS_SCRIPT'
#!/usr/bin/env bash
# INOVATECH – pacotes principais (leitura do ambiente em ~/inovatech)
# Sem set -e: o relatório deve listar tudo mesmo se pip estiver indisponível
# no venv (ex.: certos venvs uv) ou se um pip show falhar.
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'
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

echo -e "${BOLD}${CYAN}"
cat << 'INVASCII'
██╗███╗   ██╗ ██████╗ ██╗   ██╗ █████╗ ████████╗███████╗ ██████╗██╗  ██╗
██║████╗  ██║██╔═══██╗██║   ██║██╔══██╗╚══██╔══╝██╔════╝██╔════╝██║  ██║
██║██╔██╗ ██║██║   ██║██║   ██║███████║   ██║   █████╗  ██║     ███████║
██║██║╚██╗██║██║   ██║╚██╗ ██╔╝██╔══██║   ██║   ██╔══╝  ██║     ██╔══██║
██║██║ ╚████║╚██████╔╝ ╚████╔╝ ██║  ██║   ██║   ███████╗╚██████╗██║  ██║
╚═╝╚═╝  ╚═══╝ ╚═════╝   ╚═══╝  ╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚═════╝╚═╝  ╚═╝
INVASCII
echo -e "${RESET}"

echo ""
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
echo -e "  ${GREEN}✔${RESET}  ${BOLD}inovatech-verify${RESET}    → candidato confere hash de integridade"
echo -e "  ${GREEN}✔${RESET}  ${BOLD}inovatech-versions${RESET}  → confere versões do ambiente (candidato)"
echo -e "  ${GREEN}✔${RESET}  ${BOLD}inovatech-preparar-entrega${RESET} → copia stack para entrega_## e recria ambientes"
echo -e "  ${GREEN}✔${RESET}  ${BOLD}inovatech-submit${RESET}    → gera comprovante (candidato)"
echo -e "  ${GREEN}✔${RESET}  ${BOLD}inovatech-enviar-entrega${RESET} → envia ZIP ao portal via HTTPS" \
" (comissão, após liberar internet; ver gabaritos/ENTREGA-PROVA-PRATICA-API.md)"
echo -e "  ${GREEN}✔${RESET}  ${BOLD}inovatech-seal${RESET}      → selagem única (coordenação); binário" \
" é removido após uso"
echo ""
echo -e "${BOLD}Como iniciar cada projeto:${RESET}"
echo ""
echo -e "  ${CYAN}Django :${RESET}  cd backend-django && source .venv/bin/activate"
echo "            python manage.py migrate && python manage.py runserver"
echo ""
echo -e "  ${CYAN}FastAPI:${RESET}  cd backend-fastapi && .venv/bin/python -m uvicorn main:app --reload"
echo ""
echo -e "  ${CYAN}Express:${RESET}  cd backend-express && npm run dev"
echo ""
echo -e "  ${CYAN}Vanilla:${RESET}  cd frontend-vanilla && npm run dev"
echo ""
echo -e "  ${CYAN}React  :${RESET}  cd frontend-react && npm run dev"
echo ""
echo -e "${BOLD}Ordem de uso (terminal, a partir de ${BASE_DIR}):${RESET}"
echo ""
echo -e "  ${CYAN}0. Coordenação${RESET} roda ${BOLD}inovatech-seal${RESET} (padrão"
echo "     em ~/inovatech; use --dir /caminho se necessário), divulga o hash"
echo "     público; em seguida o binário é removido (uma selagem por ambiente)."
echo ""
echo -e "  ${CYAN}1. Candidato${RESET} ao chegar: ${BOLD}inovatech-verify${RESET} — compara o hash"
echo "     calculado com o hash público divulgado. Se diferir, avisa a coordenação."
echo ""
echo -e "  ${CYAN}2. Candidato${RESET} pode rodar: ${BOLD}inovatech-versions${RESET} p/ checar" \
" dependências (opcional, antes ou durante a prova)."
echo ""
echo -e "  ${CYAN}3. Candidato${RESET} roda ${BOLD}inovatech-preparar-entrega${RESET} — escolhe backend"
echo "     e frontend, informa código PP. O comando copia a stack para"
echo "     entrega_## e recria .venv/node_modules automaticamente."
echo ""
echo -e "  ${CYAN}4. Candidato${RESET} desenvolve dentro de ${BOLD}entrega_##/${RESET}."
echo "     Tudo funciona normalmente (caminhos relativos, servers, etc.)."
echo ""
echo -e "  ${CYAN}5. Ao encerrar${RESET}, cada candidato: ${BOLD}inovatech-submit${RESET}, informa" \
" nome e código PP, e anota o hash."
echo ""
echo -e "  ${CYAN}6. Comissão${RESET} (com internet restaurada): ${BOLD}inovatech-enviar-entrega${RESET}" \
" — envia a pasta de entrega (ZIP) à API; modo laboratório: nome + posição na" \
" classificação (e segredo/edição conforme doc da API)."
echo ""
success "Setup INOVATECH finalizado — ${SETUP_DATE}"
}

run_inovatech_setup "$@"
