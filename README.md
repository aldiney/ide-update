# ide-update

Instala e mantém atualizados, com um comando só, dois editores de código no Ubuntu e no Linux Mint:

- **Visual Studio Code**, da Microsoft
- **Antigravity IDE**, do Google

## O que é isso, em palavras simples

Instalar esses programas no Linux dá trabalho: é preciso achar o arquivo certo no site, baixar, instalar pelo terminal e repetir tudo a cada versão nova. O Antigravity nem avisa quando sai versão nova.

O `ide-update` faz isso por você. Você roda, escolhe no menu o que quer, digita a sua senha, e ele:

1. Confere o que já está instalado no seu computador.
2. Baixa a versão mais nova **direto dos sites oficiais** (Microsoft e Google).
3. Instala, ou atualiza se já estiver instalado.
4. Coloca o programa no menu de aplicativos, para você abrir como qualquer outro.

Depois disso, o **VS Code passa a se atualizar sozinho**, junto com as atualizações normais do sistema. Para o **Antigravity**, basta rodar o `ide-update` de novo de vez em quando: ele diz se tem versão nova e atualiza.

## Passo a passo (para quem nunca usou o terminal)

O terminal é uma janela onde você escreve comandos em vez de clicar. Você só vai precisar colar um comando nele.

### 1. Abra o Terminal

Aperte as teclas **Ctrl + Alt + T** ao mesmo tempo. Abre uma janela, geralmente preta ou roxa, com um texto parecido com `maria@computador:~$`.

Se não abrir, clique no menu de aplicativos, digite **Terminal** e clique no ícone que aparecer.

### 2. Copie o comando abaixo

Selecione o comando inteiro com o mouse e copie (botão direito, **Copiar**, ou Ctrl + C):

```bash
wget -O ide-update.sh https://raw.githubusercontent.com/aldiney/ide-update/main/ide-update.sh && bash ide-update.sh
```

### 3. Cole no Terminal e aperte Enter

No Terminal, colar é diferente: use **Ctrl + Shift + V** (as três teclas juntas), ou clique com o botão direito dentro da janela e escolha **Colar**. Depois aperte **Enter**.

### 4. Escolha o que quer fazer

Vai aparecer o que já está instalado e um menu:

```
O que está no seu computador agora:

  Visual Studio Code   não instalado (versão disponível: 1.143.0)
  Antigravity IDE      não instalado (versão disponível: 2.5.5)

O que você quer fazer?

  1) Instalar ou atualizar o Visual Studio Code
  2) Instalar ou atualizar o Antigravity IDE
  3) Os dois
  0) Sair sem fazer nada

Digite o número e aperte Enter:
```

Digite o número (por exemplo **3** para os dois) e aperte **Enter**. Nada é alterado no computador antes desse passo.

### 5. Digite a sua senha

O Terminal vai pedir uma senha. É **a mesma senha que você usa para entrar no computador**.

> **Importante:** enquanto você digita, **nada aparece na tela**, nem bolinha, nem asterisco. Não é defeito. Digite a senha normalmente e aperte **Enter**.

### 6. Se aparecer uma pergunta sobre "versão nova"

Quando uma versão saiu há menos de 7 dias, o programa avisa e pergunta se você quer instalar mesmo assim. Esperar alguns dias é uma precaução: dá tempo de alguém descobrir algum problema na versão nova.

- Digite **s** e Enter para instalar agora.
- Digite **n** e Enter para esperar. Nada é alterado; rode o programa de novo daqui a alguns dias.

### 7. Pronto

Ao terminar, aparece **"Pronto. Pode fechar esta janela."** Para abrir o programa, clique no menu de aplicativos e procure **Visual Studio Code** ou **Antigravity IDE**.

## Para atualizar depois

- **VS Code:** não precisa fazer nada, ele se atualiza sozinho com o sistema.
- **Antigravity IDE:** abra o Terminal (Ctrl + Alt + T), cole o mesmo comando do passo 2 e escolha a opção **2**. Se já estiver na versão mais nova, ele avisa e não muda nada.

Feche o Antigravity antes de atualizar. Se ele estiver aberto, o programa avisa e pede para fechar.

## Perguntas frequentes

**É seguro?**
Os programas vêm só dos endereços oficiais da Microsoft (`packages.microsoft.com`) e do Google (`antigravity.google`). O `ide-update` é um arquivo de texto que qualquer pessoa pode abrir e ler: [ide-update.sh](ide-update.sh).

**Por que ele pede a minha senha?**
Instalar programas para todo o computador exige permissão de administrador, e o Linux confirma isso pedindo a sua senha. O `ide-update` não guarda nem envia a senha.

**Apareceu "a senha não foi aceita".**
Confira se digitou certo (lembre que nada aparece na tela) e rode de novo. Se a sua conta não for de administrador, quem administra o computador precisa rodar o programa.

**Apareceu "outra janela de atualização do sistema".**
O computador estava instalando atualizações ao mesmo tempo. Espere alguns minutos e rode de novo.

**Eu já tinha instalado o VS Code pela Central de Aplicativos.**
O programa percebe e não instala um segundo VS Code. Essa versão já se atualiza sozinha pela Central.

**Meus arquivos, extensões e configurações somem ao atualizar?**
Não. Eles ficam guardados na sua pasta pessoal e a atualização só troca o programa.

**Como desinstalar?**
No Terminal, cole o comando do programa que quer remover e aperte Enter (ele pede a senha):

```bash
# Visual Studio Code
sudo apt remove code

# Antigravity IDE
sudo rm -rf /opt/antigravity-ide /usr/local/bin/antigravity-ide /usr/share/applications/antigravity-ide.desktop /usr/share/applications/antigravity-ide-url-handler.desktop
```

## Licença

Licença [MIT](LICENSE). Pode usar, copiar, modificar, fazer fork, distribuir e até vender, do jeito que quiser, sem pedir permissão. A única condição é citar a origem: manter o aviso de autoria e a licença junto com qualquer cópia ou versão modificada.

---

## Para quem entende (detalhes técnicos)

### Uso pela linha de comando

```bash
bash ide-update.sh                # menu
bash ide-update.sh status         # instalado x disponível, sem mudar nada
bash ide-update.sh vscode
bash ide-update.sh antigravity
bash ide-update.sh todos --sim    # --sim aceita versão com menos de 7 dias sem perguntar
```

Testado no Ubuntu 26.04 (Cinnamon). Roda como usuário comum e chama `sudo` só onde precisa. Antes de começar, confere se há `apt`, instala o `curl` se faltar e testa a conexão.

### Quarentena de 7 dias

A data de publicação do VS Code vem do epoch embutido na versão do pacote (`1.143.0-1792533444`); a do Antigravity, do `Last-Modified` do tar.gz. Sem terminal interativo e sem `--sim`, a resposta é tratada como "não".

### VS Code

Vem do repositório apt oficial da Microsoft, que o próprio `.deb` do site já registra. O script só cria o repositório se ele não existir (chave em `/usr/share/keyrings/microsoft.gpg`, fonte em `/etc/apt/sources.list.d/vscode.sources`) e roda `apt-get install code`. Se o VS Code existente for o snap, não faz nada.

Também cria `/etc/apt/apt.conf.d/51unattended-upgrades-vscode`, que libera a origem `code stable` no `unattended-upgrades` (por padrão ele só aceita origens do Ubuntu). Essa atualização automática **não respeita a quarentena**: o `unattended-upgrades` não tem opção de idade mínima. Para desligar, apague esse arquivo.

### Antigravity IDE

O repositório apt do Google parou na 1.23.2, e o app não se atualiza sozinho (o `updateUrl` do `product.json` aponta para `https://example.com`). O script lê a URL versionada no HTML de `https://antigravity.google/download?os=linux` e instala o tar.gz.

| O quê | Onde |
|---|---|
| App | `/opt/antigravity-ide/` (versão em `.versao`) |
| Comando | `/usr/local/bin/antigravity-ide` |
| Menu | `/usr/share/applications/antigravity-ide.desktop` |
| Login pelo navegador (`antigravity-ide://`) | `/usr/share/applications/antigravity-ide-url-handler.desktop` |

A pasta é do root e o `chrome-sandbox` fica com setuid (`4755`): com `kernel.apparmor_restrict_unprivileged_userns=1` (padrão do Ubuntu 24.04+), o Electron não abre sem isso. Extensões ficam em `~/.antigravity-ide` e configurações em `~/.config/Antigravity IDE`, fora de `/opt`, então a troca de versão não as afeta.
