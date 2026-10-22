# ide-update.sh

Instala ou atualiza o VS Code e o Antigravity IDE no Ubuntu (testado no 26.04 Cinnamon).

```bash
./ide-update.sh                # menu
./ide-update.sh status         # instalado x disponível, sem mudar nada
./ide-update.sh vscode
./ide-update.sh antigravity
./ide-update.sh todos --sim    # --sim pula a confirmação de quarentena
```

Roda como usuário comum e pede `sudo` só onde precisa.

## Quarentena de 7 dias

Se a versão mais nova foi publicada há menos de 7 dias, o script mostra a data e pergunta antes de instalar. A data do VS Code vem do epoch embutido na versão do pacote (`1.143.0-1792533444`); a do Antigravity, do `Last-Modified` do tar.gz.

## VS Code

Vem do repositório apt oficial da Microsoft, que o próprio `.deb` do site já registra. O script só cria o repositório se ele não existir e roda `apt-get install code`.

Também cria `/etc/apt/apt.conf.d/51unattended-upgrades-vscode`, que libera a origem `code stable` no `unattended-upgrades`. Com isso o VS Code passa a se atualizar sozinho junto com as atualizações diárias do Ubuntu. Essa atualização automática **não respeita a quarentena**: o `unattended-upgrades` não tem opção de idade mínima. Para desligar, apague esse arquivo.

## Antigravity IDE

O repositório apt do Google parou na 1.23.2 e o app não se atualiza sozinho (o `updateUrl` do `product.json` aponta para `https://example.com`). O script lê a URL versionada em `https://antigravity.google/download?os=linux` e instala o tar.gz.

| O quê | Onde |
|---|---|
| App | `/opt/antigravity-ide/` (versão em `.versao`) |
| Comando | `/usr/local/bin/antigravity-ide` |
| Menu | `/usr/share/applications/antigravity-ide.desktop` |
| Login pelo navegador (`antigravity-ide://`) | `/usr/share/applications/antigravity-ide-url-handler.desktop` |

Extensões ficam em `~/.antigravity-ide` e configurações em `~/.config/Antigravity IDE`, fora de `/opt`, então a troca de versão não as afeta. Feche o app antes de atualizar.
