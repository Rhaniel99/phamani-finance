# Deploy do Phamani no marvin

```
Internet ──https──▶ Cloudflare ──túnel──▶ cloudflared ─▶ web (nginx) ─▶ app (php-fpm) ─▶ postgres
                                              (tudo dentro da rede docker "phamani")
```

Nenhuma porta precisa ser aberta no roteador. O HTTPS é da Cloudflare. O nginx só escuta em
`127.0.0.1:8686`, para testar de dentro do servidor.

| Container | Função |
|---|---|
| `phamani_app` | PHP-FPM com o código e os assets já compilados |
| `phamani_web` | nginx |
| `phamani_scheduler` | `schedule:work`: recorrências, débito automático, saldo |
| `phamani_postgres` | banco (volume `phamani_pgdata`) |
| `phamani_backup` | `pg_dump` diário em `/media/dados/backups/phamani`, guarda 30 dias |
| `phamani_cloudflared` | Cloudflare Tunnel |

O consumo total é de uns 600 MB de RAM, com limites definidos no compose.

---

## 1. Mover o DNS do lukisa.com.br para a Cloudflare (uma vez só)

1. Crie uma conta em https://dash.cloudflare.com, clique em **Add a domain**, informe `lukisa.com.br` e escolha o plano **Free**.
2. A Cloudflare importa os registros DNS atuais. Confira se nada ficou de fora (e-mail/MX, por exemplo).
3. Ela mostra **dois nameservers** (algo como `xxx.ns.cloudflare.com`).
4. No **registro.br**: abra o domínio, vá em **DNS → Alterar servidores DNS**, troque pelos dois da Cloudflare e salve.
   Se o DNSSEC estiver ativo no registro.br, desative antes.
5. Espere a Cloudflare mostrar o domínio como **Active**. Leva de alguns minutos a algumas horas, e ela envia um e-mail quando terminar.

## 2. Criar o túnel

1. No painel da Cloudflare, abra **Zero Trust → Networks → Tunnels → Create a tunnel**.
2. Escolha **Cloudflared** e dê o nome `phamani`.
3. Na tela de instalação, escolha **Docker** e copie **só o token** (o texto longo depois de `--token`, que começa com `eyJ`).
   Ele vai no `CLOUDFLARE_TUNNEL_TOKEN`. Não rode o comando que aparece ali.
4. Em **Public Hostname**, preencha:
   - Subdomain: `phamani`
   - Domain: `lukisa.com.br`
   - Service: **HTTP** → `web:8000`
5. Salve. O túnel fica "Inactive" até o primeiro deploy, e isso é esperado.

## 3. Google OAuth

No Google Cloud Console, em **APIs e serviços → Credenciais**, abra o seu cliente OAuth e adicione:

- **Origens JavaScript autorizadas:** `https://phamani.lukisa.com.br`
- **URIs de redirecionamento autorizados:** `https://phamani.lukisa.com.br/auth/google/callback`

Em **Tela de consentimento OAuth → Público-alvo**, faça uma destas duas coisas:
- clique em **Publicar app**, para qualquer conta Google conseguir entrar; ou
- deixe em "Teste" e adicione em **Usuários de teste** as contas que vão usar (a sua e a da sua esposa).

## 4. Preparar o servidor (uma vez só)

```bash
# Pastas do ambiente e dos backups
mkdir -p ~/apps/phamani
sudo mkdir -p /media/dados/backups/phamani
sudo chown $USER:$USER /media/dados/backups/phamani

# O usuário precisa estar no grupo docker (o runner roda como ele)
groups | grep -q docker || { sudo usermod -aG docker $USER; echo "saia e entre de novo no SSH"; }
```

Crie o arquivo de ambiente **fora do repositório**:

```bash
# Pegue o modelo do repositório (ou copie e cole o conteúdo)
curl -fsSL https://raw.githubusercontent.com/<usuario>/<repo>/main/.env.production.example \
  -o ~/apps/phamani/.env.production     # repo privado: copie o arquivo à mão
chmod 600 ~/apps/phamani/.env.production

# Gere os segredos e cole no arquivo
echo "APP_KEY=base64:$(openssl rand -base64 32)"
echo "DB_PASSWORD=$(openssl rand -hex 24)"

nano ~/apps/phamani/.env.production
```

Preencha `APP_KEY`, `DB_PASSWORD`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` e `CLOUDFLARE_TUNNEL_TOKEN`.

> **Guarde o APP_KEY e a DB_PASSWORD** num gerenciador de senhas. Se trocar o `APP_KEY`, todo mundo é deslogado.
> Se perder a `DB_PASSWORD`, os backups continuam valendo, mas o volume atual fica inacessível sem ela.

Se a porta `8686` já estiver em uso no marvin, troque o `APP_PORT`.

## 5. Registrar o runner do GitHub para este repositório

O runner que já existe é de outro projeto. Este precisa de um próprio, com o label `phamani`.

1. No GitHub, abra o repositório e vá em **Settings → Actions → Runners → New self-hosted runner → Linux x64**.
2. No marvin, use uma pasta separada:

```bash
mkdir ~/actions-runner-phamani && cd ~/actions-runner-phamani
# Rode os comandos "Download" que o GitHub mostrar (curl ... e tar xzf ...)

./config.sh --url https://github.com/<usuario>/<repo> --token <TOKEN_DA_TELA> \
  --name marvin-phamani --labels phamani --unattended

sudo ./svc.sh install $USER
sudo ./svc.sh start
```

3. Em **Settings → Environments**, crie o environment `production`. Se quiser, marque **Required reviewers** para aprovar cada deploy.

O workflow `.github/workflows/deploy.yml` funciona assim:
- em todo push e PR, roda os testes no GitHub (`ubuntu-latest`);
- se os testes passarem na `main`, roda `deploy/deploy.sh` no marvin.

## 6. Primeiro deploy

Você pode rodar pelo GitHub (**Actions → Testes e deploy → Run workflow**) ou à mão:

```bash
git clone https://github.com/<usuario>/<repo>.git ~/apps/phamani/src
cd ~/apps/phamani/src
./deploy/deploy.sh
```

O script faz o build das imagens, sobe o Postgres, roda as migrations, sobe tudo e testa `http://127.0.0.1:8686/up`.

Para conferir:

```bash
docker ps --filter name=phamani
docker logs phamani_cloudflared --tail 20     # deve mostrar "Registered tunnel connection"
```

Depois abra https://phamani.lukisa.com.br e entre com o Google.

## Dia a dia

```bash
cd <pasta do checkout>          # a do runner fica em ~/actions-runner-phamani/_work/<repo>/<repo>
alias pdc='docker compose -p phamani -f docker-compose.prod.yml --env-file ~/apps/phamani/.env.production'

pdc logs -f app                  # logs
pdc exec app php artisan tinker  # console
pdc exec app php artisan phamani:process-due   # rodar o agendamento na mão
pdc restart                      # reiniciar
```

O deploy é só dar `git push` na `main`.

## Backups

- O backup roda todo dia, a partir do horário em que o container subiu. Fica em `/media/dados/backups/phamani/phamani-AAAA-MM-DD_HHMM.sql.gz` e os arquivos com mais de 30 dias são apagados.
- Para fazer um backup agora: `docker restart phamani_backup` (o primeiro dump sai na hora).
- Para restaurar:

```bash
./deploy/restore-backup.sh                                  # lista os backups
./deploy/restore-backup.sh phamani-2026-11-18_0300.sql.gz  # pede confirmação
```

> Os backups ficam no mesmo HD do servidor. Para ter uma cópia fora de casa, sincronize essa pasta
> com outro lugar de vez em quando (Google Drive com rclone, outro disco etc.).

## Segurança

- Firewall: nada precisa ficar aberto para a internet. Se for ligar o `ufw`, libere o SSH e a LAN (por causa do Samba e dos outros serviços):

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.100.0/24
sudo ufw enable
```

  Atenção: portas publicadas pelo Docker passam por cima do ufw. As do Phamani estão presas em `127.0.0.1`, então não ficam expostas.
- O `.env.production` fica com `chmod 600` e fora do git (o `.gitignore` já o ignora).
- **Renove o lukisa.com.br antes de jan/2027** no registro.br. Se ele expirar, o site cai.
