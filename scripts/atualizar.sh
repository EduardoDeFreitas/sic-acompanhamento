#!/usr/bin/env bash
# Atualiza os dados do painel (index.html) a partir do Git do SIC.
#
# Uso:  scripts/atualizar.sh            -> só regera o index.html
#       scripts/atualizar.sh --push     -> regera, faz commit e push (só na branch main)
#
# Lê sempre origin/homolog e origin/main do repositório do SIC (faz fetch antes),
# então não depende da branch que estiver aberta lá.
# Caminho do SIC: variável SIC_REPO, padrão ~/sic-corrigir-actions.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")/.." && pwd)"
SIC="${SIC_REPO:-$HOME/sic-corrigir-actions}"
HTML="$AQUI/index.html"
H=origin/homolog
M=origin/main
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
log(){ echo "[$(date '+%F %T')] $*"; }

[ -d "$SIC/.git" ] || { log "Repositório do SIC não encontrado em $SIC (defina SIC_REPO)"; exit 1; }
if [ "${1:-}" = "--push" ]; then
  br=$(git -C "$AQUI" branch --show-current)
  [ "$br" = "main" ] || { log "Push só na main (branch atual: $br). Nada feito."; exit 1; }
  git -C "$AQUI" pull -q --rebase --autostash origin main
fi
log "Buscando homolog e main do SIC"
git -C "$SIC" fetch -q origin homolog main

DADOS="$TMP/dados.js"

# ---------- 1. Commits, testes por módulo ----------
git -C "$SIC" log "$H" --no-merges --format='@@%ad|%h|%s' --date=short --name-status | awk '
function tipo(s,l){l=tolower(s);
  if(l~/^revert|^voltando|^restaura|^revert\(/)return "rev";
  if(l~/^feat/)return "feat";if(l~/^fix|^fx:/)return "fix";if(l~/^(refactor|perf|chore|docs|test|ci|build|style)/)return "manut";
  if(l~/^(corrige|corrigir|corrigindo|ajusta|ajuste|ajustes|ajustando|arrumando|arrumamndo|correc|correç|resolve|evita|garante|tentando|try fix|hot fix)/)return "fix";
  if(l~/^(adiciona|adicionando|implementa|cria|criar|nova|novo|integra|inclui|add )/)return "feat";return "outro"}
function fraco(s,l){l=tolower(s);
  if(l~/regisnaldo|reginaldo|eduardo|leonardo|deus|regis|tre-ba|joguinho|o game|patrulha|metal slug/)return 1;
  if(l~/tentando|try fix|teste de fix|dnv|hot fix|mergendo|^atualizaç|^ajustando o erro|^arrumando erro|fazendo teste|mais um teste|descrição das|nn estava|^fazendo ajustes|^preenchimento$|coisas novas|^arrumando os campos|funfando|^ajustes$/)return 1;
  return length(s)<14}
function mod(p){p=tolower(p);
  if(p~/automaticmonthly|reportscheduler|clientreportdispatch|reportoccurrence|automatic_monthly/)return "ra";
  if(p~/features\/bug|\/bug\/|features\/noc-ia|ticket-triage|tickettriage|sic-voice-gateway/)return "noc";
  if(p~/features\/agents|platform_backend\/agent\/|email-triage|emailtriage|emailgateway|pages\/automations|automation/)return "automacoes";
  if(p~/precificacao|pages\/comercial/)return "comercial";
  if(p~/media-library|medialibrary/)return "midia";
  if(p~/features\/people|peoplecontroller|\/people|people[a-z]*\.java/)return "dp";
  if(p~/pages\/pmo.*parceir|parceiro/)return "parceiros";
  if(p~/pages\/pmo|\/pmo|pmo[a-z]*\.java/)return "pmo";
  if(p~/pages\/projects|dataverse|baseproject/)return "projetos";
  if(p~/pages\/contracts|components\/contracts|agreement|sysaidcontract|contract/)return "contratos";
  if(p~/features\/atendimentos|pages\/atendimento|features\/workforce|service-catalog|knowledge|licenc|ticketbase|ticketsnapshot|equipes|sysaidticket/)return "atendimentos";
  if(p~/pages\/financeiro|custos|riscos|gerenciais\/melhorias/)return "operacional";
  if(p~/signature|assinatura/)return "assinatura";
  if(p~/feedback/)return "feedback";
  if(p~/datamart|pages\/operacao/)return "analises";
  if(p~/pages\/admin|security\/|integrationapi|\/mcp\/|features\/developers|features\/communication|branchmanager/)return "admin";
  if(p~/pages\/gerenciais|report|exportsysaid|renderer/)return "relatorios";
  if(p~/layout\/|sidebar|pages\/hub|pages\/index|dashboardpage/)return "inicio";
  if(p~/cadastros\/clientes|empresa|clientes/)return "clientes";
  return ""}
function fecha(k,l,sep){if(h=="")return;l="";sep="";for(k in vis){l=l sep "\"" k "\"";sep=","}
  t2=subj;gsub(/\\/,"\\\\",t2);gsub(/"/,"\\\"",t2);gsub(/\t/," ",t2);sub(/^[A-Za-z]+(\([^)]*\))?: */,"",t2);if(baixo)t2="";
  printf "%s[\"%s\",\"%s\",\"%s\",[%s],%d,\"%s\"]\n",(n++?",":""),d,h,tp,l,tst,substr(t2,1,120);delete vis;tst=0}
BEGIN{print "window.SIC_COMMITS=["}
/^@@/{fecha();s=substr($0,3);i=index(s,"|");d=substr(s,1,i-1);s=substr(s,i+1);i=index(s,"|");h=substr(s,1,i-1);subj=substr(s,i+1);tp=tipo(subj);baixo=fraco(subj);next}
NF>=2{st=$1;p=$NF;m=mod(p);if(m!="")vis[m]=1;
  if(substr(st,1,1)=="A"&&(p~/Test\.java$/||p~/\.test\.tsx?$/)){tst++;tm=m==""?"outros":m;testes[tm]++}}
END{fecha();print "];";printf "window.SIC_TESTES_MOD={";sep="";for(k in testes){printf "%s\"%s\":%d",sep,k,testes[k];sep=","}print "};"}' > "$DADOS"

HOJE=$(git -C "$SIC" log -1 --format=%cd --date=short "$H")
INICIO=$(git -C "$SIC" log "$H" --no-merges --format=%ad --date=short | tail -1)

# ---------- 2. Pendências por semana, promoções e deploys ----------
{
  printf 'window.SIC_PEND={'
  sep=''
  d=$(date -d "$INICIO -$(( $(date -d "$INICIO" +%u) - 1 )) day" +%F)   # segunda da 1a semana
  while [ "$(date -d "$d" +%s)" -le "$(date -d "$HOJE" +%s)" ]; do
    fim=$(date -d "$d +6 day" +%F)
    h=$(git -C "$SIC" rev-list -1 --before="$fim 23:59" "$H"); m=$(git -C "$SIC" rev-list -1 --before="$fim 23:59" "$M")
    if [ -n "$m" ] && [ -n "$h" ]; then printf '%s"%s":%s' "$sep" "$d" "$(git -C "$SIC" rev-list --no-merges --count "$m..$h")"; sep=','; fi
    d=$(date -d "$d +7 day" +%F)
  done
  printf '};\nwindow.SIC_PROMOCOES=['
  git -C "$SIC" log "$M" --first-parent --format='"%ad"' --date=short | tr '\n' ',' | sed 's/,$//'
  printf '];\n'
  printf 'window.SIC_DEPLOYS={'
  git -C "$SIC" log "$H" --first-parent --date=short --format=%cd | sort | uniq -c | awk '{printf "%s\"%s\":%s",s,$2,$1;s=","}'
  printf '};\n'
} >> "$DADOS"

# ---------- 3. Resumo calculado (substitui os números fixos do objeto REPO) ----------
inv(){ # $1 = commit -> "telas,controladores,testes"
  git -C "$SIC" ls-tree -r --name-only "$1" | awk '/src\/pages\/.*\.tsx$/{p++} /Controller\.java$/{c++} /Test\.java$|\.test\.tsx?$/{t++} END{printf "%d,%d,%d",p,c,t}'
}
INV=""
mes=$(date -d "$(date -d "$INICIO" +%Y-%m-01) +1 month" +%F)
while [ "$(date -d "$mes" +%s)" -le "$(date -d "$HOJE" +%s)" ]; do
  c=$(git -C "$SIC" rev-list -1 --before="$mes 00:00" "$H")
  [ -n "$c" ] && INV="$INV${INV:+,}['$(date -d "$mes" +%d/%m)',$(inv "$c")]"
  mes=$(date -d "$mes +1 month" +%F)
done
INV="$INV${INV:+,}['$(date -d "$HOJE" +%d/%m)',$(inv "$H")]"

COMMIT=$(git -C "$SIC" rev-parse --short=8 "$H")
EM=$(git -C "$SIC" log -1 --format=%cd --date=format:'%d/%m/%Y %H:%M' "$H")
TOTAL=$(git -C "$SIC" rev-list --no-merges --count "$H")
MAINEM=$(git -C "$SIC" log -1 --first-parent --format=%cd --date=format:'%d/%m/%Y' "$M")
SOHML=$(git -C "$SIC" rev-list --no-merges --count "$M..$H")
DDMM=$(date -d "$HOJE" +%d/%m)
NOMES=(jan fev mar abr mai jun jul ago set out nov dez)
LONGOS=(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)
MI=$((10#$(date -d "$HOJE" +%m) - 1))

sed -n '/^window.SIC_COMMITS=\[/,/^\];/p' "$DADOS" | sed '1d;$d' | awk -F'"' -v ini="${INICIO:0:7}" -v fim="${HOJE:0:7}" '
BEGIN{split("jan fev mar abr mai jun jul ago set out nov dez",N," ");
  y=substr(ini,1,4)+0;m=substr(ini,6,2)+0;
  while(1){k=sprintf("%04d-%02d",y,m);ms[++nm]=k;lb[nm]=N[m];if(k==fim)break;m++;if(m>12){m=1;y++}}}
{d=substr($2,1,7);t=$6;T[t" "d]++;
 s=$0;sub(/^[^[]*\[[^[]*\[/,"",s);sub(/\].*/,"",s);n=split(s,a,",");
 g=(t=="feat")?1:(t=="fix")?2:3;
 for(i=1;i<=n;i++){x=a[i];gsub(/"/,"",x);if(x!=""){MD[x]=1;C[x" "d" "g]++}}}
END{
 printf "meses:[";for(i=1;i<=nm;i++)printf "%s[\x27%s\x27,\x27%s\x27]",(i>1?",":""),ms[i],lb[i];printf "],\n";
 printf "tipos:{";split("feat fix manut outro rev",TP," ");for(j=1;j<=5;j++){printf "%s%s:[",(j>1?",":""),TP[j];for(i=1;i<=nm;i++)printf "%s%d",(i>1?",":""),T[TP[j]" "ms[i]];printf "]"}printf "},\n";
 printf "mods:{";f=0;for(x in MD){printf "%s%s:[",(f++?",":""),x;for(i=1;i<=nm;i++)printf "%s[%d,%d,%d]",(i>1?",":""),C[x" "ms[i]" 1"],C[x" "ms[i]" 2"],C[x" "ms[i]" 3"];printf "]"}printf "},\n"}' > "$TMP/resumo.js"

{
  echo "window.SIC_AUTO={"
  echo "base:{commit:'$COMMIT',em:'$EM',branch:'homolog',inicio:'$(date -d "$INICIO" +%d/%m/%Y)',commits:$TOTAL,mainEm:'$MAINEM',soHomolog:$SOHML,parcial:'${NOMES[$MI]} até $DDMM',parcialLongo:'${LONGOS[$MI]} até $DDMM'},"
  cat "$TMP/resumo.js"
  echo "inventario:[$INV],"
  echo "soHml:'$(git -C "$SIC" log --no-merges --format=%h "$M..$H" | tr '\n' ' ' | sed 's/ $//')'"
  echo "};"
} >> "$DADOS"

# ---------- 4. Troca o bloco de dados no index.html ----------
grep -q '^window.SIC_COMMITS=\[' "$HTML" || { log "Bloco de dados não encontrado no index.html"; exit 1; }
awk -v f="$DADOS" '
/^window\.SIC_COMMITS=\[/{while((getline l < f)>0)print l;pula=1;next}
pula&&/^<\/script>/{pula=0}
!pula{print}' "$HTML" > "$TMP/index.html"
mv "$TMP/index.html" "$HTML"
log "Dados atualizados até $HOJE ($COMMIT): $TOTAL alterações, $SOHML só na homolog"

# ---------- 5. Commit e push ----------
if [ "${1:-}" = "--push" ]; then
  cd "$AQUI"
  if git diff --quiet -- index.html; then log "Sem mudanças. Nada a enviar."; exit 0; fi
  git add index.html
  git commit -q -m "Atualiza dados do SIC até $(date -d "$HOJE" +%d/%m/%Y) ($COMMIT)"
  git push -q origin main
  log "Enviado para origin/main"
fi
