# Atualização do laboratório INOVATECH

Este fluxo alinha máquinas preparadas com uma versão antiga de
`setup_inovatech.sh` à versão atual, com **reset completo** da árvore de
projetos base (como na reexecução documentada no próprio setup), nova selagem
e checagem de integridade.

## Pré-condições

- `LAB_ROOT` efetivo é **`${HOME}/inovatech`** (exigido por
  `inovatech-preparar-entrega` embutido no setup).
- **sudo** disponível para gravar em `/usr/local/bin`.
- Preferencialmente **internet** no modo online.

## Modo online (recomendado)

Na máquina candidato (usuário do laboratório):

```bash
cd ~/inovatech
bash /caminho/do/rep/atualizar_inovatech_lab.sh --yes
```

Ou usando o script publicado no GitHub (ajuste a URL ao seu fork/branch):

```bash
cd ~/inovatech
curl -fsSL https://raw.githubusercontent.com/RomuloBarrosPI/inovatech-lab-prep/main/atualizar_inovatech_lab.sh | bash -s -- --yes
```

Confira se essa URL reflete a última revisão no GitHub (`git pull` no clone e
compare, ou abra o raw no navegador). O `curl` sempre baixa o que está em
`main`; alterações só no clone local só valem se você **enviar commit e push**
ou usar o caminho local abaixo.

Opções úteis:

- `--setup-src /caminho/setup_inovatech.sh` — não baixa da rede.
- `--no-seal` — só recria o ambiente; a coordenação sela depois.
- `INOVATECH_ASSUME_YES=1` — equivalente a `--yes`.

Ao final, o script executa `inovatech-seal` (salvo com `--no-seal`) e
`inovatech-verify`. **Divulgue o novo hash público** contido em
`.seal/hash_publico.txt`.

## Modo offline

### 1) Gerar o pacote (máquina referência com lab já atual)

Com os cinco projetos base em `~/inovatech` e `inovatech-verify` no `PATH`:

```bash
bash outros/gerar_pacote_atualizacao_offline.sh \
  --output /media/pendrive/inovatech-offline-$(date +%Y%m%d).tar.gz
```

O arquivo inclui `inovatech/` (sem `.seal/`, `entrega/` e `entrega_##/`), uma
cópia de `setup_inovatech.sh` e `MANIFEST.txt` com
`EXPECTED_VERIFY_HASH`.

### 2) Aplicar no laboratório

```bash
cd ~/inovatech
bash /caminho/atualizar_inovatech_lab.sh \
  --offline-bundle /media/pendrive/inovatech-offline-YYYYMMDD.tar.gz \
  --yes
```

Se o hash após a selagem divergir do manifest, o script encerra com erro.

## Testes de regressão (auditoria)

Com o lab atualizado e selado:

```bash
bash outros/inovatech_hash_diagnose.sh --dir ~/inovatech
bash outros/simular_fluxo_candidato.sh
bash outros/testar_todas_combinacoes_lab.sh
```

Para raiz não padrão (somente em ambiente de teste): defina `INOVATECH_ROOT` e,
se necessário, `INOVATECH_NVM_DIR` apontando para o `~/.nvm` original do
usuário. Ver comentários no topo de `outros/simular_fluxo_candidato.sh` e
`outros/testar_todas_combinacoes_lab.sh`.

Logs do atualizador: `~/inovatech_update_logs/`.

## Ver também

- Instruções aos fiscais: `FAQ_FISCAIS.md`
- Setup completo: `setup_inovatech.sh`
