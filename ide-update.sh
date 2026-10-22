#!/usr/bin/env bash
# Instala ou atualiza o VS Code (repositório apt da Microsoft) e o
# Antigravity IDE (tar.gz oficial do Google, que não tem apt atual).
set -euo pipefail

QUARENTENA_DIAS=7
ASSUME_SIM=0
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

msg() { printf '==> %s\n' "$*"; }
erro() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

uso() {
	cat <<'EOF'
Uso: ide-update.sh [ação] [--sim]

Ações:
  status        versão instalada x disponível, sem mudar nada
  vscode        instala ou atualiza o VS Code
  antigravity   instala ou atualiza o Antigravity IDE
  todos         os dois
  (sem ação)    menu interativo

--sim  responde "sim" na confirmação de quarentena
EOF
}

confirmar() {
	(( ASSUME_SIM )) && return 0
	local resposta
	read -r -p "$1 [s/N] " resposta
	[[ $resposta == [sS]* ]]
}

# Pede confirmação quando a versão tem menos de QUARENTENA_DIAS.
# $1 = descrição, $2 = epoch da publicação
checar_quarentena() {
	local descricao=$1 publicado=$2 dias
	dias=$(( ($(date +%s) - publicado) / 86400 ))
	(( dias >= QUARENTENA_DIAS )) && return 0
	msg "$descricao foi publicado em $(date -d "@$publicado" '+%Y-%m-%d %H:%M') (há $dias dia(s); quarentena de $QUARENTENA_DIAS)."
	confirmar "Instalar mesmo assim?"
}

vscode_instalado() {
	dpkg-query -W -f='${db:Status-Status} ${Version}\n' code 2>/dev/null | awk '$1 == "installed" {print $2}'
}

vscode_candidato() {
	LC_ALL=C apt-cache policy code 2>/dev/null | awk '/Candidate:/ {print $2}'
}

vscode_garantir_repo() {
	grep -rqs 'packages.microsoft.com/repos/code' /etc/apt/sources.list /etc/apt/sources.list.d/ && return 0
	msg "Configurando o repositório apt da Microsoft"
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
	msg "Ativando a atualização automática do VS Code pelo unattended-upgrades"
	sudo tee "$VSCODE_UNATTENDED" >/dev/null <<'EOF'
// Criado por ide-update.sh: permite ao unattended-upgrades atualizar o VS Code.
Unattended-Upgrade::Origins-Pattern {
	"origin=code stable,label=code stable";
};
EOF
}

atualizar_vscode() {
	vscode_garantir_repo
	msg "Atualizando a lista de pacotes"
	sudo apt-get update -qq

	local atual candidato
	atual=$(vscode_instalado)
	candidato=$(vscode_candidato)
	[[ -n $candidato && $candidato != "(none)" ]] || erro "o pacote code não aparece no apt. Confira $VSCODE_SOURCES."

	if [[ $atual == "$candidato" ]]; then
		msg "VS Code já está na última versão ($atual)."
	# O sufixo da versão do pacote é o epoch do build: 1.143.0-1792533444.
	elif checar_quarentena "VS Code $candidato" "${candidato##*-}"; then
		sudo apt-get install -y code
		msg "VS Code ${atual:+$atual -> }$candidato"
	else
		msg "VS Code mantido em ${atual:-não instalado}."
	fi

	vscode_garantir_unattended
}

ag_arquitetura() {
	case $(uname -m) in
		x86_64) echo linux-x64 ;;
		aarch64) echo linux-arm ;;
		*) erro "arquitetura sem build do Antigravity: $(uname -m)" ;;
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

	msg "Baixando Antigravity IDE $versao"
	curl -fL --progress-bar -o "$TMP_DIR/antigravity.tar.gz" "$url"
	tar -xzf "$TMP_DIR/antigravity.tar.gz" -C "$TMP_DIR"
	[[ -x $pacote/antigravity-ide ]] || erro "o pacote baixado não tem a estrutura esperada (Antigravity IDE/antigravity-ide)."
	printf '%s\n' "$versao" >"$pacote/.versao"

	msg "Instalando em $AG_DIR"
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
	local url versao atual ultima_modificacao
	url=$(ag_url_atual || true)
	[[ -n $url ]] || erro "não achei a URL do tar.gz em $AG_PAGINA. A página pode ter mudado de formato."
	versao=$(ag_versao_da_url "$url")
	atual=$(ag_instalado)

	if [[ $atual == "$versao" ]]; then
		msg "Antigravity IDE já está na última versão ($atual)."
		return 0
	fi

	ultima_modificacao=$(curl -fsSIL "$url" | tr -d '\r' | awk -F': ' 'tolower($1) == "last-modified" {print $2}' | tail -n1 || true)
	[[ -n $ultima_modificacao ]] || erro "o servidor não informou a data de publicação de $url."
	if ! checar_quarentena "Antigravity IDE $versao" "$(date -d "$ultima_modificacao" +%s)"; then
		msg "Antigravity IDE mantido em ${atual:-não instalado}."
		return 0
	fi

	if pgrep -f "^$AG_DIR/" >/dev/null; then
		erro "o Antigravity IDE está aberto. Feche e rode de novo."
	fi

	ag_instalar "$url" "$versao"
	msg "Antigravity IDE ${atual:+$atual -> }$versao"
}

status() {
	local ag_url
	ag_url=$(ag_url_atual || true)
	printf '%-16s instalado: %-28s disponível: %s\n' "VS Code" "$(vscode_instalado || true)" "$(vscode_candidato)"
	printf '%-16s instalado: %-28s disponível: %s\n' "Antigravity IDE" "$(ag_instalado)" "${ag_url:+$(ag_versao_da_url "$ag_url")}"
}

menu() {
	local opcao
	cat >&2 <<'EOF'
1) VS Code
2) Antigravity IDE
3) Os dois
4) Status
EOF
	read -r -p "Opção: " opcao
	case $opcao in
		1) echo vscode ;;
		2) echo antigravity ;;
		3) echo todos ;;
		4) echo status ;;
		*) erro "opção inválida: $opcao" ;;
	esac
}

main() {
	local acao="" arg
	for arg in "$@"; do
		case $arg in
			--sim|-y) ASSUME_SIM=1 ;;
			-h|--help) uso; exit 0 ;;
			*) acao=$arg ;;
		esac
	done
	[[ -n $acao ]] || acao=$(menu)

	case $acao in
		status) status ;;
		vscode) atualizar_vscode ;;
		antigravity) atualizar_antigravity ;;
		todos) atualizar_vscode; atualizar_antigravity ;;
		*) uso; exit 1 ;;
	esac
}

main "$@"
