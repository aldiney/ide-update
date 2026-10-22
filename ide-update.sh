#!/usr/bin/env bash
# Instala ou atualiza o VS Code (repositório apt da Microsoft) e o
# Antigravity IDE (tar.gz oficial do Google, que não tem apt atual).
set -euo pipefail

QUARENTENA_DIAS=7
ASSUME_SIM=0
SENHA_OK=0
TMP_DIR=""
trap '[[ -z $TMP_DIR ]] || rm -rf "$TMP_DIR"' EXIT

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

confirmar() {
	(( ASSUME_SIM )) && return 0
	if [[ ! -t 0 ]]; then
		aviso "Sem teclado para responder; vou considerar que a resposta é não."
		return 1
	fi
	local resposta
	read -r -p "$1 Digite s para sim ou n para não e aperte Enter: " resposta
	[[ $resposta == [sS]* ]]
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

# Pede confirmação quando a versão tem menos de QUARENTENA_DIAS.
# $1 = nome com versão, $2 = epoch da publicação
checar_quarentena() {
	local descricao=$1 publicado=$2 dias
	dias=$(( ($(date +%s) - publicado) / 86400 ))
	(( dias >= QUARENTENA_DIAS )) && return 0
	printf '\n'
	aviso "$descricao saiu há $dias dia(s), em $(date -d "@$publicado" '+%d/%m/%Y')."
	cat <<EOF
  Por segurança, o recomendado é esperar $QUARENTENA_DIAS dias antes de instalar uma versão
  nova: dá tempo de alguém descobrir algum problema nela. Se você responder
  não, nada é alterado e você pode rodar o programa de novo daqui a alguns dias.
EOF
	confirmar "Instalar mesmo assim?"
}

vscode_instalado() {
	dpkg-query -W -f='${db:Status-Status} ${Version}\n' code 2>/dev/null | awk '$1 == "installed" {print $2}'
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
	elif checar_quarentena "O VS Code $(versao_curta "$candidato")" "${candidato##*-}"; then
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
	if ! checar_quarentena "O Antigravity IDE $(versao_curta "$versao")" "$(date -d "$publicado" +%s)"; then
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
