#!/usr/bin/env bash
# Instala ou atualiza o VS Code (repositório apt da Microsoft) e o
# Antigravity IDE (tar.gz oficial do Google, que não tem apt atual).
set -euo pipefail

QUARENTENA_DIAS=7
ASSUME_SIM=0
SENHA_OK=0
TMP_DIR=""
ANALISE_DIR=""

VSCODE_KEYRING=/usr/share/keyrings/microsoft.gpg
VSCODE_SOURCES=/etc/apt/sources.list.d/vscode.sources
VSCODE_UNATTENDED=/etc/apt/apt.conf.d/51unattended-upgrades-vscode

AG_PAGINA='https://antigravity.google/download?os=linux'
AG_DIR=/opt/antigravity-ide
AG_LINK=/usr/local/bin/antigravity-ide
AG_DESKTOP=/usr/share/applications/antigravity-ide.desktop
AG_DESKTOP_URL=/usr/share/applications/antigravity-ide-url-handler.desktop

if [[ -t 1 ]]; then
	VERDE=$'\e[32m' AMARELO=$'\e[33m' VERMELHO=$'\e[31m' NEGRITO=$'\e[1m' NORMAL=$'\e[0m'
else
	VERDE="" AMARELO="" VERMELHO="" NEGRITO="" NORMAL=""
fi

# Tela e trace (set -x) vão para o log; o trace fica só no arquivo, pelo fd 3.
LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.log"
LOG="$LOG_DIR/ide-update-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"
exec 3>>"$LOG"
exec > >(tee -a "$LOG") 2>&1
TEE_PID=$!
BASH_XTRACEFD=3
PS4='+ linha ${LINENO}: '
set -x

ao_sair() {
	local codigo=$?
	[[ -z $TMP_DIR ]] || rm -rf "$TMP_DIR"
	[[ -z $ANALISE_DIR ]] || rm -rf "$ANALISE_DIR"
	if (( codigo != 0 )); then
		printf '\n%s✖ O programa parou antes de terminar. Detalhes em: %s%s\n' "$VERMELHO" "$LOG" "$NORMAL"
	fi
	# Espera o tee gravar o resto, senão o prompt do terminal volta antes da última linha.
	exec >&- 2>&-
	wait "$TEE_PID" 2>/dev/null || true
}
trap ao_sair EXIT

info() { printf '\n%s▶ %s%s\n' "$NEGRITO" "$*" "$NORMAL"; }
ok() { printf '%s✔ %s%s\n' "$VERDE" "$*" "$NORMAL"; }
aviso() { printf '%s! %s%s\n' "$AMARELO" "$*" "$NORMAL"; }
erro() { printf '\n%s✖ %s%s\n' "$VERMELHO" "$*" "$NORMAL" >&2; exit 1; }

uso() {
	cat <<'EOF'
Uso: bash ide-update.sh [ação] [--sim]

Sem ação, abre um menu com as opções.

Ações:
  status        mostra o que está instalado e o que tem de versão nova
  vscode        instala ou atualiza o Visual Studio Code
  antigravity   instala ou atualiza o Antigravity IDE
  todos         os dois

--sim  instala versão nova mesmo com menos de 7 dias, sem perguntar
EOF
}

abertura() {
	cat <<EOF
${NEGRITO}ide-update${NORMAL}: instala e atualiza editores de código no Ubuntu e no Linux Mint

  - Visual Studio Code, da Microsoft
  - Antigravity IDE, do Google

Nada é alterado antes de você escolher uma opção no menu.
EOF
}

versao_curta() { printf '%s' "${1%%-*}"; }

# Explica o pedido de senha uma vez, antes do primeiro sudo.
pedir_senha() {
	(( SENHA_OK )) && return 0
	if ! sudo -n true 2>/dev/null; then
		cat <<'EOF'

Para instalar programas, o computador vai pedir a SUA senha (a mesma que
você usa para entrar no computador). Enquanto você digita, nada aparece
na tela, nem asterisco. É normal: digite a senha e aperte Enter.

EOF
		sudo -v || erro "A senha não foi aceita, ou a sua conta não tem permissão de administrador. Rode o programa de novo e confira a senha."
	fi
	SENHA_OK=1
}

checar_sistema() {
	command -v apt-get >/dev/null \
		|| erro "Este programa funciona só em Ubuntu, Linux Mint e sistemas parecidos (que usam apt)."

	if ! command -v curl >/dev/null; then
		info "Falta um programa auxiliar (curl), que serve para baixar arquivos. Vou instalá-lo primeiro."
		pedir_senha
		sudo apt-get install -y -qq curl >/dev/null || erro "Não consegui instalar o curl. Confira a conexão com a internet e rode de novo."
		ok "curl instalado."
	fi

	curl -fsS --max-time 20 -o /dev/null https://packages.microsoft.com/ \
		|| erro "Sem conexão com a internet (ou ela está muito lenta). Confira o Wi-Fi ou o cabo e rode de novo."
}

# Uma fonte que falha vira arquivo ausente, e a análise diz que não conseguiu verificar.
baixar_fonte() {
	curl -fsSL --compressed --max-time 15 -o "$ANALISE_DIR/$1" "$2" 2>/dev/null || rm -f "$ANALISE_DIR/$1"
}

# A API do GitHub permite 60 consultas por hora sem login: gasta no máximo 2 aqui.
# A tag pode demorar a sair depois do pacote no apt (a 1.144.1 saiu assim); o teste
# pelo raw não conta nessa cota, e sem tag a comparação usa a branch da versão.
baixar_fontes_vscode() {
	local instalada=$1 candidata=$2 minor destino repo=https://api.github.com/repos/microsoft/vscode
	minor=${candidata%.*}
	baixar_fonte alertas.json "$repo/security-advisories?per_page=100"
	baixar_fonte notas.md "https://raw.githubusercontent.com/microsoft/vscode-docs/main/release-notes/v${minor//./_}.md"
	[[ ${instalada%.*} == "$minor" ]] || return 0
	destino=$candidata
	curl -fsSI --max-time 15 -o /dev/null "https://raw.githubusercontent.com/microsoft/vscode/$candidata/package.json" 2>/dev/null \
		|| destino=release/$minor
	printf '%s' "$destino" >"$ANALISE_DIR/destino"
	baixar_fonte comparacao.json "$repo/compare/$instalada...$destino"
}

# Lê as fontes baixadas e grava resumo.txt e detalhes.txt em ANALISE_DIR.
# $1 = vscode ou antigravity, $2 = versão instalada (vazia se não houver), $3 = versão nova
gerar_analise() {
	python3 -I - "$1" "$ANALISE_DIR" "$2" "$3" "$QUARENTENA_DIAS" <<'PYTHON'
import json
import os
import re
import sys

app, pasta, instalada, candidata, dias_quarentena = sys.argv[1:6]

LIMITE_LINHAS = 30
LARGURA_LINHA = 150
GRAVIDADES = {"critical": "crítica", "high": "alta", "medium": "média", "low": "baixa"}
ORDEM_GRAVIDADE = list(GRAVIDADES)
SECOES_FORA_DO_RESUMO = {"Release recap", "Release highlights"}


def numeros(versao):
    return tuple(int(n) for n in re.findall(r"\d+", versao)[:3])


def ler(nome):
    try:
        with open(os.path.join(pasta, nome), encoding="utf-8", errors="replace") as arquivo:
            return arquivo.read()
    except OSError:
        return None


def ler_json(nome):
    texto = ler(nome)
    if texto is None:
        return None
    try:
        return json.loads(texto)
    except ValueError:
        return None


# O texto vem da internet: sem isso, uma sequência de escape mexeria no terminal.
def limpar(texto):
    texto = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", texto)
    texto = re.sub(r"[`*\\]", "", texto)
    texto = re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", texto).strip()
    return texto if len(texto) <= LARGURA_LINHA else texto[: LARGURA_LINHA - 3] + "..."


def na_faixa(faixa, versao):
    comparacoes = {
        "<": lambda a, b: a < b,
        "<=": lambda a, b: a <= b,
        ">": lambda a, b: a > b,
        ">=": lambda a, b: a >= b,
        "=": lambda a, b: a == b,
    }
    condicoes = re.findall(r"(<=|>=|<|>|=)\s*([\d.]+)", faixa or "")
    return bool(condicoes) and all(
        comparacoes[operador](numeros(versao), numeros(alvo)) for operador, alvo in condicoes
    )


def afeta(alerta, versao):
    return any(na_faixa(v.get("vulnerable_version_range"), versao) for v in alerta.get("vulnerabilities") or [])


def ordenar_alertas(alertas):
    return sorted(alertas, key=lambda a: ORDEM_GRAVIDADE.index(a.get("severity")) if a.get("severity") in GRAVIDADES else 9)


def linhas_alertas(alertas):
    return [
        f"  [{GRAVIDADES.get(a.get('severity'), 'sem gravidade')}] {a.get('cve_id') or a.get('ghsa_id')}: {limpar(a.get('summary') or '')}"
        for a in ordenar_alertas(alertas)
    ]


def contagem_alertas(alertas):
    partes = []
    for gravidade, nome in GRAVIDADES.items():
        quantos = sum(a.get("severity") == gravidade for a in alertas)
        if quantos:
            partes.append(f"{quantos} {nome}{'s' if quantos > 1 else ''}")
    return ", ".join(partes)


def plural(quantos, singular, varios):
    return f"{quantos} {singular if quantos == 1 else varios}"


# Título e lista de cada seção das notas, sem o texto corrido que abre o documento.
def topicos_das_notas(notas):
    linhas = []
    fora = True
    for titulo in re.findall(r"^(##+ .+)$", notas, flags=re.M):
        nivel, texto = titulo.split(" ", 1)
        texto = limpar(texto)
        if nivel == "##" and texto == "Thank you":
            break
        if nivel == "##":
            fora = texto in SECOES_FORA_DO_RESUMO
            if not fora:
                linhas.append(f"  {texto}")
        elif not fora:
            linhas.append(f"    - {texto}")
    return linhas


def commits_da_comparacao(comparacao):
    if not isinstance(comparacao, dict) or not isinstance(comparacao.get("commits"), list):
        return None
    commits = []
    for commit in comparacao["commits"]:
        titulo = commit.get("commit", {}).get("message", "").split("\n")[0]
        if titulo.startswith(f"Bump version to {candidata}"):
            break
        if not titulo.startswith("Bump version"):
            commits.append(limpar(titulo))
    return commits


def analisar_vscode():
    resultado = {"seguranca_confirmada": False, "seguranca_possivel": False, "versao_afetada": False}
    alertas = ler_json("alertas.json")
    alertas = alertas if isinstance(alertas, list) else None
    notas = ler("notas.md")
    mesma_serie = bool(instalada) and numeros(instalada)[:2] == numeros(candidata)[:2]

    atualizacoes = []
    for versao, texto in re.findall(r"^\*\*Update ([\d.]+)\*\*: (.+)$", notas or "", flags=re.M):
        if numeros(versao) <= numeros(candidata) and (not instalada or numeros(versao) > numeros(instalada)):
            atualizacoes.append((versao, limpar(texto), "security" in texto.lower()))
    notas_citam_seguranca = bool(instalada) and any(a[2] for a in atualizacoes)

    corrigidos = afetam_a_nova = []
    if alertas is not None:
        afetam_a_nova = [a for a in alertas if afeta(a, candidata)]
        if instalada:
            corrigidos = [a for a in alertas if afeta(a, instalada) and not afeta(a, candidata)]

    if afetam_a_nova:
        resultado["versao_afetada"] = True
        seguranca = f"ATENÇÃO: esta versão tem {plural(len(afetam_a_nova), 'falha publicada', 'falhas publicadas')} ({contagem_alertas(afetam_a_nova)})"
    elif corrigidos:
        resultado["seguranca_confirmada"] = True
        seguranca = f"SIM: corrige {plural(len(corrigidos), 'falha', 'falhas')} da sua versão ({contagem_alertas(corrigidos)})"
    elif notas_citam_seguranca:
        resultado["seguranca_confirmada"] = True
        seguranca = "SIM: as notas da versão dizem que ela corrige falhas de segurança"
    elif alertas is None:
        resultado["sem_dados"] = True
        seguranca = "não consegui verificar (fonte fora do ar ou limite de consultas do GitHub)"
    else:
        alvo = "a sua versão" if instalada else "esta versão"
        seguranca = f"nenhum alerta publicado até agora para {alvo}"

    detalhes = []
    if afetam_a_nova:
        detalhes += ["Falhas publicadas que afetam esta versão:"] + linhas_alertas(afetam_a_nova) + [""]
    if corrigidos:
        detalhes += ["Falhas de segurança que esta versão corrige na sua:"] + linhas_alertas(corrigidos) + [""]
    if atualizacoes:
        detalhes += ["Atualizações desta série:"] + [f"  {v}: {t}" for v, t, _ in atualizacoes] + [""]

    serie = ".".join(str(n) for n in numeros(candidata)[:2])
    pagina = "https://code.visualstudio.com/updates/v" + serie.replace(".", "_")
    links = [pagina]
    if corrigidos or afetam_a_nova:
        links.append("https://github.com/microsoft/vscode/security/advisories")

    if mesma_serie:
        commits = commits_da_comparacao(ler_json("comparacao.json"))
        if commits is None:
            tipo = "correção (não consegui listar as alterações)"
        else:
            tamanho = "correção pequena" if len(commits) <= 5 else "correção"
            tipo = f"{tamanho} ({plural(len(commits), 'alteração', 'alterações')})"
            detalhes += ["Alterações desta correção:"] + [f"  - {c}" for c in commits] + [""]
            links.insert(0, f"https://github.com/microsoft/vscode/compare/{instalada}...{ler('destino')}")
        resultado["so_correcao"] = True
    else:
        if instalada:
            saltos = numeros(candidata)[1] - numeros(instalada)[1]
            salto = f", {plural(saltos, 'versão mensal', 'versões mensais')} à frente da sua" if numeros(candidata)[0] == numeros(instalada)[0] else ""
            tipo = f"novidades (série {serie}{salto})"
        else:
            tipo = f"instalação nova da série {serie}"
        if notas is None:
            detalhes += ["Não consegui ler as notas desta versão: veja a página abaixo."]
        else:
            detalhes += [f"Novidades da série {serie}:"] + topicos_das_notas(notas)

    resultado.update(tipo=tipo, seguranca=seguranca, detalhes=detalhes, links=links)
    return resultado


def entradas_antigravity(changelog):
    inicio = re.search(r"^## Antigravity IDE", changelog, flags=re.M)
    if not inicio:
        return None
    secao = changelog[inicio.start() :]
    fim = re.search(r"^## (?!Antigravity IDE)", secao, flags=re.M)
    secao = secao[: fim.start()] if fim else secao

    entradas = []
    blocos = re.split(r"^### \[v([\d.]+)\]\([^\n]*\n", secao, flags=re.M)
    for versao, corpo in zip(blocos[1::2], blocos[2::2]):
        categoria = None
        entrada = {"versao": versao, "titulo": "", "data": "", "novidades": [], "correcoes": []}
        for linha in corpo.split("\n"):
            linha = linha.strip()
            if linha.startswith("### ") and not entrada["titulo"]:
                entrada["titulo"] = limpar(linha[4:])
            elif re.fullmatch(r"\w+ \d{1,2}, \d{4}", linha):
                entrada["data"] = linha
            elif re.fullmatch(r"\*\*\w+:?\*\*:?", linha):
                categoria = "novidades" if "Improvements" in linha else "correcoes"
            elif linha.startswith("*") and categoria:
                entrada[categoria].append(limpar(linha.lstrip("* ")))
        entradas.append(entrada)
    return entradas


def analisar_antigravity():
    resultado = {"seguranca_confirmada": False, "seguranca_possivel": False, "versao_afetada": False}
    links = ["https://antigravity.google/docs/changelog"]
    changelog = ler("changelog.md")
    entradas = entradas_antigravity(changelog) if changelog is not None else None

    if entradas is None:
        return {**resultado, "sem_dados": True, "tipo": "não consegui ler o changelog",
                "seguranca": "não consegui verificar (fonte fora do ar)", "detalhes": [], "links": links}

    novas = [e for e in entradas if numeros(e["versao"]) <= numeros(candidata)
             and (numeros(e["versao"]) > numeros(instalada) if instalada else numeros(e["versao"]) == numeros(candidata))]
    if not novas:
        return {**resultado, "sem_dados": True, "tipo": "o changelog ainda não registra esta versão",
                "seguranca": "não consegui verificar (a versão não está no changelog)", "detalhes": [], "links": links}

    termos = re.compile(r"\b(security|vulnerab\w*|cve-\d+|exploit\w*)\b", re.I)
    citacoes = [l for e in novas for l in [e["titulo"]] + e["correcoes"] + e["novidades"] if termos.search(l)]
    tem_novidade = any(e["novidades"] for e in novas)
    tem_correcao = any(e["correcoes"] for e in novas)

    if citacoes:
        resultado["seguranca_possivel"] = True
        seguranca = "POSSÍVEL: o changelog menciona segurança (leia antes de decidir)"
    else:
        seguranca = "sem menção a segurança no changelog (a única fonte disponível para o Antigravity)"

    if tem_novidade and tem_correcao:
        tipo = "novidades e correções"
    elif tem_correcao:
        tipo = "correção"
        resultado["so_correcao"] = True
    else:
        tipo = "novidades"
    if len(novas) > 1:
        tipo += f" ({len(novas)} versões à frente da sua)"

    detalhes = []
    if citacoes:
        detalhes += ["Trechos sobre segurança:"] + [f"  - {c}" for c in citacoes] + [""]
    for entrada in novas:
        detalhes.append(f"v{entrada['versao']} ({entrada['data']}): {entrada['titulo']}")
        for nome, chave in (("Correções", "correcoes"), ("Novidades", "novidades")):
            if entrada[chave]:
                detalhes += [f"  {nome}:"] + [f"    - {item}" for item in entrada[chave]]
        detalhes.append("")

    resultado.update(tipo=tipo, seguranca=seguranca, detalhes=detalhes, links=links)
    return resultado


def recomendar(r):
    if r["versao_afetada"]:
        return "não instalar esta versão: a própria versão nova tem falha publicada. Espere a próxima."
    if not instalada:
        return "instalação nova, sem versão antiga exposta na sua máquina. Pode instalar agora ou esperar: a escolha é sua."
    if r["seguranca_confirmada"]:
        return ("instalar agora: ficar na sua versão é mais arriscado do que não esperar.\n"
                "                A quarentena protege contra pacote adulterado, e o changelog não prova que\n"
                "                este está íntegro. Aqui, o risco da falha conhecida pesa mais.")
    if r["seguranca_possivel"]:
        return "ler o que mudou antes de decidir."
    if r.get("sem_dados"):
        return "esperar, porque não consegui verificar o conteúdo desta versão."
    if r.get("so_correcao"):
        return f"pode esperar os {dias_quarentena} dias, a não ser que você tenha o problema descrito."
    return f"esperar os {dias_quarentena} dias: não há correção de segurança conhecida."


resultado = analisar_vscode() if app == "vscode" else analisar_antigravity()

with open(os.path.join(pasta, "resumo.txt"), "w", encoding="utf-8") as resumo:
    resumo.write(f"  Tipo:         {resultado['tipo']}\n")
    resumo.write(f"  Segurança:    {resultado['seguranca']}\n")
    resumo.write(f"  Recomendação: {recomendar(resultado)}\n")

linhas = resultado["detalhes"]
while linhas and not linhas[-1]:
    linhas.pop()
if len(linhas) > LIMITE_LINHAS:
    linhas = linhas[:LIMITE_LINHAS] + [f"... e mais {len(linhas) - LIMITE_LINHAS} linhas na página completa."]
with open(os.path.join(pasta, "detalhes.txt"), "w", encoding="utf-8") as detalhes:
    for linha in linhas:
        detalhes.write(linha + "\n")
    detalhes.write("\nTexto em inglês, como publicado pelo fornecedor. Página completa:\n")
    for link in resultado["links"]:
        detalhes.write(f"  {link}\n")
PYTHON
}

# $1 = vscode ou antigravity, $2 = versão instalada, $3 = versão nova
analisar_versao() {
	local app=$1 instalada candidata=$3
	instalada=$(versao_curta "$2")
	candidata=$(versao_curta "$candidata")
	[[ -z $ANALISE_DIR ]] || rm -rf "$ANALISE_DIR"
	ANALISE_DIR=$(mktemp -d)

	if [[ $app == vscode ]]; then
		printf 'https://code.visualstudio.com/updates\n' >"$ANALISE_DIR/link"
	else
		printf 'https://antigravity.google/docs/changelog\n' >"$ANALISE_DIR/link"
	fi

	if ! command -v python3 >/dev/null; then
		aviso "Não consegui analisar esta versão: falta o programa python3 no computador."
		return 0
	fi
	echo "Conferindo o que mudou nesta versão..."
	if [[ $app == vscode ]]; then
		baixar_fontes_vscode "$instalada" "$candidata"
	else
		baixar_fonte changelog.md https://antigravity.google/docs/changelog.md
	fi
	gerar_analise "$app" "$instalada" "$candidata" 2>&3 \
		|| aviso "Não consegui analisar esta versão: as fontes vieram num formato inesperado."
}

mostrar_detalhes() {
	printf '\n'
	if [[ -f $ANALISE_DIR/detalhes.txt ]]; then
		cat "$ANALISE_DIR/detalhes.txt"
	else
		printf 'Página com o que mudou:\n  %s\n' "$(cat "$ANALISE_DIR/link")"
	fi
}

mostrar_resumo() {
	if [[ -f $ANALISE_DIR/resumo.txt ]]; then
		printf '\n'
		cat "$ANALISE_DIR/resumo.txt"
	fi
}

# Devolve 0 para instalar. Enter vazio repete a pergunta: decidir é do usuário.
perguntar_quarentena() {
	local opcao
	while true; do
		cat <<'EOF'

  1) Ler o que mudou
  2) Instalar agora
  3) Esperar (nada é alterado)

EOF
		read -r -p "Digite o número e aperte Enter: " opcao || return 1
		case $opcao in
			1) mostrar_detalhes ;;
			2) return 0 ;;
			3) return 1 ;;
			*) aviso "Opção \"$opcao\" não existe. Digite 1, 2 ou 3." ;;
		esac
	done
}

# Com menos de QUARENTENA_DIAS, mostra o conteúdo da versão e pergunta. Devolve 0 para instalar.
# $1 = vscode ou antigravity, $2 = nome para exibir, $3 = versão instalada, $4 = versão nova, $5 = epoch da publicação
checar_quarentena() {
	local app=$1 nome=$2 instalada=$3 candidata=$4 publicado=$5 dias tem_agora=""
	dias=$(( ($(date +%s) - publicado) / 86400 ))
	(( dias >= QUARENTENA_DIAS )) && return 0

	[[ -z $instalada ]] || tem_agora=" Você tem a $(versao_curta "$instalada")."
	printf '\n'
	aviso "O $nome $(versao_curta "$candidata") saiu há $dias dia(s), em $(date -d "@$publicado" '+%d/%m/%Y').$tem_agora"
	cat <<EOF
  O recomendado é esperar $QUARENTENA_DIAS dias antes de instalar uma versão nova: dá tempo
  de alguém descobrir algum problema nela. A exceção é quando ela corrige uma falha
  de segurança. Se você esperar, nada é alterado: rode o programa de novo depois.
EOF
	analisar_versao "$app" "$instalada" "$candidata"
	mostrar_resumo

	(( ASSUME_SIM )) && return 0
	if [[ ! -t 0 ]]; then
		aviso "Sem teclado para responder; vou considerar que a resposta é não."
		return 1
	fi
	perguntar_quarentena
}

vscode_instalado() {
	# Sem o pacote, o dpkg-query sai com 1 e o pipefail derrubaria o script sem mensagem.
	{ dpkg-query -W -f='${db:Status-Status} ${Version}\n' code 2>/dev/null || true; } | awk '$1 == "installed" {print $2}'
}

vscode_candidato() {
	LC_ALL=C apt-cache policy code 2>/dev/null | awk '/Candidate:/ && $2 != "(none)" {print $2}'
}

vscode_snap() {
	command -v snap >/dev/null && snap list code >/dev/null 2>&1
}

vscode_tem_repo() {
	grep -rqs 'packages.microsoft.com/repos/code' /etc/apt/sources.list /etc/apt/sources.list.d/
}

vscode_garantir_repo() {
	vscode_tem_repo && return 0
	info "Cadastrando a loja oficial da Microsoft no sistema, de onde o VS Code é baixado e atualizado."
	curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee "$VSCODE_KEYRING" >/dev/null
	sudo tee "$VSCODE_SOURCES" >/dev/null <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: $VSCODE_KEYRING
EOF
}

vscode_garantir_unattended() {
	[[ -f $VSCODE_UNATTENDED ]] && return 0
	sudo tee "$VSCODE_UNATTENDED" >/dev/null <<'EOF'
// Criado por ide-update.sh: permite ao unattended-upgrades atualizar o VS Code.
Unattended-Upgrade::Origins-Pattern {
	"origin=code stable,label=code stable";
};
EOF
	ok "Atualização automática do VS Code ativada: ele vai se atualizar sozinho junto com o sistema."
}

atualizar_vscode() {
	info "Visual Studio Code"
	if vscode_snap && [[ -z $(vscode_instalado) ]]; then
		ok "O VS Code deste computador foi instalado pela Central de Aplicativos (snap) e já se atualiza sozinho por lá. Nada a fazer."
		return 0
	fi
	pedir_senha
	vscode_garantir_repo
	echo "Conferindo qual é a versão mais nova..."
	sudo apt-get update -qq \
		|| erro "Não consegui consultar as versões. Se outra janela de atualização do sistema estiver aberta, espere ela terminar e rode de novo."

	local atual candidato
	atual=$(vscode_instalado)
	candidato=$(vscode_candidato)
	[[ -n $candidato ]] || erro "O VS Code não apareceu na loja da Microsoft. Rode de novo daqui a alguns minutos."

	if [[ $atual == "$candidato" ]]; then
		ok "O VS Code já está na versão mais nova ($(versao_curta "$atual")). Nada a fazer."
	# O sufixo da versão do pacote é o epoch do build: 1.143.0-1792533444.
	elif checar_quarentena vscode "VS Code" "$atual" "$candidato" "${candidato##*-}"; then
		echo "Baixando e instalando. Pode levar alguns minutos..."
		sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o DPkg::Lock::Timeout=300 code >/dev/null \
			|| erro "A instalação do VS Code falhou. Se outra janela de atualização do sistema estiver aberta, espere ela terminar e rode de novo."
		if [[ -n $atual ]]; then
			ok "VS Code atualizado: $(versao_curta "$atual") → $(versao_curta "$candidato")."
		else
			ok "VS Code $(versao_curta "$candidato") instalado. Para abrir, procure \"Visual Studio Code\" no menu de aplicativos."
		fi
	else
		echo "Nada foi alterado no VS Code."
	fi

	vscode_garantir_unattended
}

ag_arquitetura() {
	case $(uname -m) in
		x86_64) echo linux-x64 ;;
		aarch64) echo linux-arm ;;
		*) erro "O Antigravity IDE não tem versão para este tipo de computador ($(uname -m))." ;;
	esac
}

# A página de download traz a URL versionada no HTML estático:
# .../antigravity/stable/2.5.5-4923483625488384/linux-x64/Antigravity%20IDE.tar.gz
ag_url_atual() {
	local arq
	arq=$(ag_arquitetura)
	curl -fsSL --compressed "$AG_PAGINA" \
		| grep -oE "https://[^\"' ]+/antigravity/stable/[^/]+/$arq/Antigravity%20IDE\.tar\.gz" \
		| sort -u | head -n1
}

ag_versao_da_url() {
	sed -E 's#.*/stable/([^/]+)/.*#\1#' <<<"$1"
}

ag_instalado() {
	cat "$AG_DIR/.versao" 2>/dev/null || true
}

# $1 = cabeçalhos HTTP, $2 = nome do cabeçalho
cabecalho() {
	tr -d '\r' <<<"$1" | awk -F': ' -v nome="$2" 'tolower($1) == nome {print $2}' | tail -n1
}

ag_criar_desktop() {
	sudo tee "$AG_DESKTOP" >/dev/null <<EOF
[Desktop Entry]
Name=Antigravity IDE
Comment=IDE com agentes do Google
GenericName=Text Editor
Exec=$AG_DIR/antigravity-ide %F
Icon=$AG_DIR/resources/app/resources/linux/code.png
Type=Application
StartupNotify=false
StartupWMClass=Antigravity IDE
Categories=TextEditor;Development;IDE;
Actions=new-empty-window;
Keywords=antigravity;

[Desktop Action new-empty-window]
Name=Nova janela vazia
Exec=$AG_DIR/antigravity-ide --new-window %F
Icon=$AG_DIR/resources/app/resources/linux/code.png
EOF
	# O login pelo navegador volta para o app por antigravity-ide://
	sudo tee "$AG_DESKTOP_URL" >/dev/null <<EOF
[Desktop Entry]
Name=Antigravity IDE - URL Handler
Exec=$AG_DIR/antigravity-ide --open-url %U
Icon=$AG_DIR/resources/app/resources/linux/code.png
Type=Application
NoDisplay=true
StartupNotify=true
Categories=TextEditor;Development;IDE;
MimeType=x-scheme-handler/antigravity-ide;
EOF
	sudo update-desktop-database -q /usr/share/applications || true
}

ag_instalar() {
	local url=$1 versao=$2 pacote
	TMP_DIR=$(mktemp -d /var/tmp/ide-update.XXXXXX)
	pacote="$TMP_DIR/Antigravity IDE"

	curl -fL --progress-bar -o "$TMP_DIR/antigravity.tar.gz" "$url" \
		|| erro "O download foi interrompido. Confira a internet e rode de novo; nada foi alterado."
	echo "Descompactando..."
	tar -xzf "$TMP_DIR/antigravity.tar.gz" -C "$TMP_DIR"
	[[ -x $pacote/antigravity-ide ]] \
		|| erro "O arquivo baixado veio diferente do esperado; o Google pode ter mudado o formato. Nada foi alterado."
	printf '%s\n' "$versao" >"$pacote/.versao"

	echo "Instalando..."
	sudo rm -rf "$AG_DIR.new" "$AG_DIR.old"
	sudo mv "$pacote" "$AG_DIR.new"
	sudo chown -R root:root "$AG_DIR.new"
	# Com apparmor_restrict_unprivileged_userns=1 o Electron só abre com o sandbox setuid.
	sudo chmod 4755 "$AG_DIR.new/chrome-sandbox"
	if [[ -d $AG_DIR ]]; then
		sudo mv "$AG_DIR" "$AG_DIR.old"
	fi
	sudo mv "$AG_DIR.new" "$AG_DIR"
	sudo rm -rf "$AG_DIR.old"

	sudo ln -sfn "$AG_DIR/bin/antigravity-ide" "$AG_LINK"
	ag_criar_desktop
}

atualizar_antigravity() {
	info "Antigravity IDE"
	echo "Conferindo qual é a versão mais nova..."
	local url versao atual cabecalhos publicado tamanho
	url=$(ag_url_atual || true)
	[[ -n $url ]] || erro "Não achei o link de download na página do Antigravity ($AG_PAGINA). O Google pode ter mudado a página; procure uma versão nova deste programa."
	versao=$(ag_versao_da_url "$url")
	atual=$(ag_instalado)

	if [[ $atual == "$versao" ]]; then
		ok "O Antigravity IDE já está na versão mais nova ($(versao_curta "$atual")). Nada a fazer."
		return 0
	fi

	cabecalhos=$(curl -fsSIL "$url" || true)
	publicado=$(cabecalho "$cabecalhos" last-modified)
	tamanho=$(cabecalho "$cabecalhos" content-length)
	[[ -n $publicado ]] || erro "O site do Google não respondeu direito. Rode de novo daqui a alguns minutos."
	if ! checar_quarentena antigravity "Antigravity IDE" "$atual" "$versao" "$(date -d "$publicado" +%s)"; then
		echo "Nada foi alterado no Antigravity IDE."
		return 0
	fi

	if pgrep -f "^$AG_DIR/" >/dev/null; then
		aviso "O Antigravity IDE está aberto. Feche todas as janelas dele e rode este programa de novo."
		return 1
	fi

	pedir_senha
	echo "Baixando cerca de $(( ${tamanho:-0} / 1024 / 1024 )) MB. Pode levar alguns minutos..."
	ag_instalar "$url" "$versao"
	if [[ -n $atual ]]; then
		ok "Antigravity IDE atualizado: $(versao_curta "$atual") → $(versao_curta "$versao")."
	else
		ok "Antigravity IDE $(versao_curta "$versao") instalado. Para abrir, procure \"Antigravity IDE\" no menu de aplicativos."
	fi
	echo "  O Antigravity não se atualiza sozinho: para pegar versões novas, rode este programa de novo de vez em quando."
}

# $1 = nome, $2 = versão instalada, $3 = versão disponível
linha_status() {
	local situacao
	if [[ -z $2 ]]; then
		situacao="não instalado${3:+ (versão disponível: $(versao_curta "$3"))}"
	elif [[ -z $3 || $2 == "$3" ]]; then
		situacao="instalado, versão $(versao_curta "$2")${3:+ (em dia)}"
	else
		situacao="instalado, versão $(versao_curta "$2") ${AMARELO}(tem versão nova: $(versao_curta "$3"))${NORMAL}"
	fi
	printf '  %-20s %s\n' "$1" "$situacao"
}

status() {
	local ag_url ag_disponivel=""
	ag_url=$(ag_url_atual || true)
	[[ -z $ag_url ]] || ag_disponivel=$(ag_versao_da_url "$ag_url")
	if vscode_snap && [[ -z $(vscode_instalado) ]]; then
		printf '  %-20s %s\n' "Visual Studio Code" "instalado pela Central de Aplicativos (se atualiza sozinho)"
	else
		linha_status "Visual Studio Code" "$(vscode_instalado || true)" "$(vscode_candidato || true)"
	fi
	linha_status "Antigravity IDE" "$(ag_instalado)" "$ag_disponivel"
}

menu() {
	[[ -t 0 ]] || erro "Não consegui ler o teclado. Baixe o arquivo e rode assim: bash ide-update.sh"
	local opcao
	{
		printf '\nO que está no seu computador agora:\n\n'
		status
		cat <<'EOF'

O que você quer fazer?

  1) Instalar ou atualizar o Visual Studio Code
  2) Instalar ou atualizar o Antigravity IDE
  3) Os dois
  0) Sair sem fazer nada

EOF
	} >&2
	read -r -p "Digite o número e aperte Enter: " opcao
	case $opcao in
		1) echo vscode ;;
		2) echo antigravity ;;
		3) echo todos ;;
		0) echo sair ;;
		*) erro "Opção \"$opcao\" não existe. Rode o programa de novo e digite 1, 2, 3 ou 0." ;;
	esac
}

main() {
	local acao="" arg
	for arg in "$@"; do
		case $arg in
			--sim|-y) ASSUME_SIM=1 ;;
			-h|--help|ajuda) uso; exit 0 ;;
			*) acao=$arg ;;
		esac
	done

	[[ -n $acao ]] || abertura
	printf '\nRegistro desta execução: %s\n' "$LOG"
	checar_sistema
	if [[ -z $acao ]]; then
		acao=$(menu)
	fi

	case $acao in
		status) status; return 0 ;;
		vscode) atualizar_vscode ;;
		antigravity) atualizar_antigravity ;;
		todos) atualizar_vscode; atualizar_antigravity ;;
		sair) echo "Nada foi alterado."; return 0 ;;
		*) uso; exit 1 ;;
	esac
	printf '\n%sPronto. Pode fechar esta janela.%s\n' "$VERDE" "$NORMAL"
}

main "$@"
