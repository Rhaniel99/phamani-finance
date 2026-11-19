#!/usr/bin/env bash
# Phamani — evita o 502 quando o container do app é recriado (nginx agora resolve "app" pelo DNS do Docker),
# deploy recria app/scheduler/web sempre, e DEPLOY.md com o atalho pdc e o acesso pelo DBeaver.
# Uso: na raiz do projeto ->  bash fix-nginx-502.sh
set -euo pipefail
[ -f artisan ] && [ -f docker/nginx/prod.conf ] || { echo "Rode na raiz do projeto Phamani."; exit 1; }
BACKUP=".backup-$(date +%Y%m%d%H%M%S)"
backup() { if [ -f "$1" ]; then mkdir -p "$BACKUP/$(dirname "$1")"; cp "$1" "$BACKUP/$1"; fi; }
write() { backup "$1"; mkdir -p "$(dirname "$1")"; cat > "$1"; echo "  ok  $1"; }
echo "Aplicando arquivos (backup em $BACKUP/):"

write 'docker/nginx/prod.conf' <<'PHAMANI_EOF'
server {
    listen 8000;
    server_name _;
    root /var/www/html/public;
    index index.php;

    client_max_body_size 20M;
    server_tokens off;

    error_log  stderr warn;
    access_log off;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    charset utf-8;

    # Resolve o "app" pelo DNS do Docker a cada 10s (em vez de só na subida do nginx):
    # quando o container do app é recriado ele ganha outro IP, e sem isso o nginx dá 502.
    resolver 127.0.0.11 valid=10s ipv6=off;
    set $php_upstream app:9000;

    location / {
        try_files $uri /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    # O nginx só tem /public; o PHP roda no container "app" com o mesmo caminho.
    location ~ ^/index\.php(/|$) {
        fastcgi_pass $php_upstream;
        fastcgi_split_path_info ^(.+\.php)(/.*)$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME /var/www/html/public/index.php;
        fastcgi_param DOCUMENT_ROOT /var/www/html/public;
        fastcgi_buffer_size 32k;
        fastcgi_buffers 8 16k;
        fastcgi_hide_header X-Powered-By;
    }

    location /build/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
PHAMANI_EOF

write 'deploy/deploy.sh' <<'PHAMANI_EOF'
#!/usr/bin/env bash
# Deploy do Phamani no servidor (usado pelo GitHub Actions e também à mão).
#   ./deploy/deploy.sh                 → build + sobe + migra
# Variáveis opcionais:
#   PHAMANI_ENV_FILE  (padrão: /home/pholaroid/apps/phamani/.env.production)
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE="${PHAMANI_ENV_FILE:-/home/pholaroid/apps/phamani/.env.production}"
export PHAMANI_ENV_FILE="$ENV_FILE"

if [ ! -f "$ENV_FILE" ]; then
  echo "✗ Arquivo de ambiente não encontrado: $ENV_FILE" >&2
  echo "  Copie .env.production.example para lá e preencha." >&2
  exit 1
fi

dc() { docker compose -p phamani -f docker-compose.prod.yml --env-file "$ENV_FILE" "$@"; }

BACKUP_DIR="$(grep -E '^BACKUP_DIR=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')"
mkdir -p "${BACKUP_DIR:-/media/dados/backups/phamani}"

echo "→ Build das imagens"
dc build --pull

echo "→ Banco"
dc up -d postgres
dc up -d --wait postgres

echo "→ Migrations"
dc run --rm --no-deps app php artisan migrate --force --no-interaction

echo "→ Subindo os serviços"
dc up -d --remove-orphans
# Garante que app, scheduler e web usem as imagens recém-construídas e o .env atual
dc up -d --no-deps --force-recreate app scheduler web

echo "→ Checando a aplicação"
PORT="$(grep -E '^APP_PORT=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')"
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://127.0.0.1:${PORT:-8686}/up"; then
    echo "✓ Phamani no ar"
    docker image prune -f >/dev/null
    exit 0
  fi
  sleep 2
done

echo "✗ A aplicação não respondeu em /up. Logs:" >&2
dc logs --tail=80 app web >&2
exit 1
PHAMANI_EOF

write 'DEPLOY.md' <<'PHAMANI_EOF'
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

1. No painel da Cloudflare: **Rede → Túneis → Criar túnel → Cloudflared**, nome `phamani`.
2. Escolha **Docker** e copie o comando (botão de copiar); guarde **só o token** (começa com `eyJ`)
   → vai no `CLOUDFLARE_TUNNEL_TOKEN`.
3. A tela só deixa **Continuar** quando um conector estiver online. Para liberar, rode um temporário no marvin:
   `docker run --rm cloudflare/cloudflared:latest tunnel --no-autoupdate run --token <TOKEN>`
4. Depois de criado, abra o túnel **phamani** na lista → aba **Rotas** → **Adicionar rota → Aplicativo publicado**:
   - Hostname: `phamani` . `lukisa.com.br`
   - Service URL: `http://web:8000`
   (o registro DNS é criado automaticamente)
5. `Ctrl+C` no temporário. Até o primeiro deploy, o site responde "Error 1033" — normal.

Recomendado: **Domínios → lukisa.com.br → SSL/TLS → Certificados de borda → Sempre usar HTTPS**.

## 3. Google OAuth

No Google Cloud Console, em **APIs e serviços → Credenciais**, abra o seu cliente OAuth e adicione:

- **Origens JavaScript autorizadas:** `https://phamani.lukisa.com.br`
- **URIs de redirecionamento autorizados:** `https://phamani.lukisa.com.br/auth/google/callback`

Em **Google Auth Platform → Público-alvo**, deixe em **Testando** e adicione as contas em **Usuários de teste**
(só elas conseguem entrar). Publicar exige Branding completo e verificação do domínio — não é necessário.

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

Preencha `APP_KEY`, `DB_PASSWORD`, `ALLOWED_EMAILS`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` e `CLOUDFLARE_TUNNEL_TOKEN`.

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
# atalho (coloque no ~/.bashrc)
pdc() {
  PHAMANI_ENV_FILE=~/apps/phamani/.env.production \
  docker compose -p phamani \
    -f ~/actions-runner-phamani/_work/phamani-finance/phamani-finance/docker-compose.prod.yml \
    --env-file ~/apps/phamani/.env.production "$@"
}

pdc ps                                          # status
pdc logs -f app                                 # logs
pdc up -d --force-recreate app scheduler        # aplicar mudanças do .env.production
pdc exec app php artisan tinker                 # console
pdc exec app php artisan phamani:process-due    # rodar o agendamento na mão
```

### Banco pelo DBeaver (túnel SSH)

O Postgres escuta só em `127.0.0.1:5433` do marvin. No DBeaver: aba **SSH** → "Use SSH Tunnel",
host `192.168.100.11`, usuário `pholaroid`, chave pública; aba **Main** → host `localhost`, porta `5433`,
banco/usuário `phamani`, senha = `DB_PASSWORD`.

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
PHAMANI_EOF

chmod +x deploy/deploy.sh
echo "Pronto. Faça commit e push."
