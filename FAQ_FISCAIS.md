---
output:
  pdf_document: default
  html_document: default
---
# FAQ para Fiscais: Resolução de Problemas na Prova Prática

Este documento contém orientações para os fiscais de laboratório sobre o fluxo esperado e como agir em situações inesperadas durante a execução dos comandos de preparação e entrega da prova prática (`inovatech-preparar-entrega` e `inovatech-submit`).

**Atualização do ambiente** (reset para a versão atual do setup, com nova selagem):
veja [INSTRUCOES_ATUALIZACAO_LAB.md](INSTRUCOES_ATUALIZACAO_LAB.md).

---

## 🧭 Guia Geral: Fluxo do Candidato

### ANTES de Iniciar a Prova (Preparação)

**O que o candidato deve fazer:**
1. Abrir o terminal do sistema operacional.

2. O comando funciona globalmente de qualquer lugar, mas idealmente o terminal estará na pasta base do usuário (ex: `~` ou `~/inovatech`).

3. Executar o seguinte comando no terminal:
   ```bash
   inovatech-preparar-entrega
   ```
   
4. O sistema solicitará interativamente o **Código PP** (um número de 01 a 40), qual opção de *backend* e qual opção de *frontend* ele usará.

5. O script copiará o código-base, instalará as dependências e criará a pasta de trabalho final (ex: `~/inovatech/entrega_21`). O candidato deverá abrir seu editor de código (como o VS Code) **nesta nova pasta gerada** para iniciar a prova.

**Possíveis erros / eventos atípicos:**

- **Erro de "Comando não encontrado" (`command not found`):** Significa que aquela máquina específica não executou o setup inicial do laboratório de forma correta. O suporte técnico deve ser acionado para rodar a preparação da máquina.
- **Aviso de "Pasta já existe":** Ocorre se o candidato rodar o comando novamente usando um número PP que já foi preparado antes. O sistema perguntará se deseja sobrescrever.

**Atenção:** se o candidato confirmar (digitando `s`), **todo o trabalho que ele já desenvolveu na pasta será apagado e substituído pelos arquivos originais vazios**. Instrua-o a cancelar digitando `N` se não quiser perder o que já fez.

---

### DURANTE a Prova (Desenvolvimento e Execução)

Para testar o sistema, o candidato precisará iniciar os servidores do **Frontend** e do **Backend**. Isso exige que ele tenha **dois terminais diferentes abertos simultaneamente** no seu editor ou no sistema operacional.

**Como iniciar o Frontend (React ou Vanilla):**

1. No terminal 1, navegar até a pasta do frontend da sua entrega:
   `cd ~/inovatech/entrega_XX/frontend-escolhido`
2. Executar:
   `npm run dev`

**Como iniciar o Backend (Depende da escolha do candidato):**

No terminal 2, o candidato deve navegar até a pasta do seu backend e executá-lo. O script de preparação já deixou tudo pronto (ambientes virtuais e dependências instaladas).

- **Se for Django:**
  `cd ~/inovatech/entrega_XX/backend-django`
  `source .venv/bin/activate` *(ativa o ambiente virtual)*
  `python manage.py runserver`
- **Se for FastAPI:**
  `cd ~/inovatech/entrega_XX/backend-fastapi`
  `source .venv/bin/activate` *(ativa o ambiente virtual)*
  `python -m uvicorn main:app --reload`
- **Se for Express (Node.js):**
  `cd ~/inovatech/entrega_XX/backend-express`
  `npm run dev`

**Possíveis erros / eventos atípicos ao rodar os serviços:**

- **Erro "Address already in use" ou "Port is already in use":**
  Significa que o candidato já iniciou o servidor antes, e ele continua rodando oculto em outra aba ou janela de terminal. 
  
  *Como agir:* Peça para ele procurar o terminal que está "preso" rodando o servidor e pressionar `Ctrl + C` para pará-lo, ou fechar o terminal antigo antes de tentar rodar de novo.
- **Erro "ModuleNotFoundError" (Python) ou "Command not found":**
  Acontece se o candidato esquecer de ativar o ambiente virtual (comando `source .venv/bin/activate`) ou tentar rodar o servidor estando na pasta errada (ex: na raiz `entrega_XX` em vez de dentro da pasta do backend).
  
  *Como agir:* Verifique em qual pasta o terminal está apontando e se o prefixo `(.venv)` aparece no terminal dele. Peça para ele entrar na pasta correta e rodar o comando de ativação primeiro.
- **Erro indicando "Missing module" no Node.js:**
  Às vezes o candidato pode acidentalmente deletar a pasta `node_modules`.
  
  *Como agir:* Basta navegar até a pasta do frontend ou do backend express e rodar o comando `npm install` para baixar tudo novamente.

---

### DEPOIS de Finalizar a Prova (Entrega)

**O que o candidato deve fazer:**

1. Garantir que todo o código no editor esteja salvo e interromper eventuais servidores de teste que estejam rodando no terminal.
2. Abrir o terminal. O comando detectará o projeto automaticamente se rodado da pasta `~/inovatech` ou de dentro da própria pasta de entrega `~/inovatech/entrega_XX`.
3. Executar o comando:
   ```bash
   inovatech-submit
   ```
4. O sistema localizará a pasta com o código e perguntará interativamente os dados do candidato: o **Código PP** correto e o **Nome Completo**.
5. O script processará a entrega, gerando um arquivo compactado inviolável e exibindo na tela um **Hash SHA-256** (uma sequência grande de letras e números). Esse hash é o recibo digital do candidato, e ele deve ser instruído a fotografar a tela ou anotar essa informação antes de sair.

**Possíveis erros / eventos atípicos:**

- **Erro: "Pasta de entrega não encontrada":** Ocorre se a pasta automática (`entrega_XX`) foi deletada, movida para fora de `~/inovatech/` ou renomeada para um nome fora do padrão (ex: `minha_prova`).
  *Como agir:* O fiscal deve localizar onde a pasta do candidato foi parar e rodar o comando apontando exatamente para esse diretório com o parâmetro `--dir`:
  `inovatech-submit --dir /caminho/completo/para/a/pasta/do/candidato`
- **Erro: "Várias pastas de entrega encontradas":** Ocorre se o candidato executou a preparação várias vezes com números diferentes (gerando, por exemplo, a `entrega_12` e a `entrega_21`). O sistema, por segurança, trava e não sabe qual das duas entregar.
  
  *Como agir:* Oriente o candidato a apagar a pasta que não contém o seu código atual ou execute o comando manualmente indicando qual é a pasta certa:
  `inovatech-submit --dir ~/inovatech/entrega_21`

---

## ❓ Perguntas Frequentes de Cenários Específicos

### 1. O candidato digitou letras ou o próprio nome em vez do seu "Código PP" no momento de preparar a entrega. O que acontece?

**O que ocorre:**  

O script possui uma validação rigorosa. Se o candidato digitar qualquer caractere que não seja um número de 1 ou 2 dígitos (de 01 a 40), o sistema abortará a operação imediatamente exibindo um erro. Nenhum código será copiado ou perdido.

**Como o fiscal deve agir:**  

Oriente o candidato a executar o comando `inovatech-preparar-entrega` novamente, prestando atenção para digitar apenas o seu número (Código PP) corretamente.

---

### 2. O candidato digitou o número errado (ex: era o 21 e digitou 12) ao rodar `inovatech-preparar-entrega`, mas percebeu **antes** de começar a codificar.

**O que ocorre:**  

O sistema criará uma pasta com o número errado (ex: `entrega_12`) contendo uma cópia do código base, mas o código original na área de trabalho do candidato permanece intacto.

**Como o fiscal deve agir:**  

1. Peça para o candidato rodar o comando `inovatech-preparar-entrega` novamente, dessa vez digitando o número correto (ex: 21). Isso criará a pasta correta (`entrega_21`).

2. **Importante:** Oriente o candidato a apagar a pasta que foi gerada por engano (`entrega_12`). Se ele não apagar, o problema de "várias pastas encontradas" (descrito na sessão de entrega) acontecerá no final da prova.

---

### 3. O candidato percebeu que digitou o número errado na preparação da entrega, mas pode simplesmente **renomear** a pasta (ex: de `entrega_12` para `entrega_21`)?

**O que ocorre:**  

Embora renomear a pasta pareça a solução mais simples e funcione visualmente, **isso não é recomendado e pode causar problemas técnicos**. Especialmente no caso de projetos Python (Django ou FastAPI), a pasta do ambiente virtual (`.venv`) salva caminhos absolutos baseados no nome original da pasta no momento em que é criada. Ao renomear a pasta pai, o ambiente virtual pode "quebrar", gerando erros ao tentar rodar o servidor ou instalar pacotes.

**Como o fiscal deve agir:**  

Não permita que o candidato apenas renomeie a pasta. Se ele ainda não começou a programar, a instrução deve ser: **"Apague a pasta com o nome errado e rode o comando `inovatech-preparar-entrega` novamente"**. Isso garantirá que o ambiente virtual seja recriado com os caminhos corretos.

---

### 4. O candidato digitou o número errado, mas **só percebeu o erro após ter iniciado o projeto** e já escreveu muito código na pasta errada.

**O que ocorre:**  

Se ele rodar o `inovatech-preparar-entrega` novamente com o número correto, o script puxará os arquivos originais (em branco/sem as modificações dele), o que pode causar pânico desnecessário e o risco de sobrescrever trabalho se ele tentar mover arquivos manualmente.

**Como o fiscal deve agir:**  

**Oriente o candidato a continuar trabalhando na pasta com o nome errado.**  

A arquitetura do sistema é segura e separa o nome físico da pasta da real identidade do candidato. No final da prova, quando ele rodar o comando `inovatech-submit`, o script de entrega perguntará interativamente no terminal o "Código PP" e o "Nome completo". 

Basta que o candidato **digite o número e o nome corretos nesse momento final**. O sistema irá compactar e gerar o comprovante usando o código preenchido na hora da entrega, ignorando o nome errado que a pasta possui.
