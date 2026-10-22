#!/usr/bin/env bash
# Instala ou atualiza o VS Code (repositório apt da Microsoft).
set -euo pipefail

QUARENTENA_DIAS=7
ASSUME_SIM=0

VSCODE_KEYRING=/usr/share/keyrings/microsoft.gpg
VSCODE_SOURCES=/etc/apt/sources.list.d/vscode.sources
VSCODE_UNATTENDED=/etc/apt/apt.conf.d/51unattended-upgrades-vscode

msg() { printf '==> %s\n' "$*"; }
erro() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

uso() {
	cat <<'EOF'
Uso: ide-update.sh [ação] [--sim]

Ações:
  status        versão instalada x disponível, sem mudar nada
  vscode        instala ou atualiza o VS Code
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

status() {
	printf '%-16s instalado: %-28s disponível: %s\n' "VS Code" "$(vscode_instalado || true)" "$(vscode_candidato)"
}

menu() {
	local opcao
	cat >&2 <<'EOF'
1) VS Code
2) Status
EOF
	read -r -p "Opção: " opcao
	case $opcao in
		1) echo vscode ;;
		2) echo status ;;
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
		*) uso; exit 1 ;;
	esac
}

main "$@"
