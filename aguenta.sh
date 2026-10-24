#!/usr/bin/env bash
# aguenta: diz o que um celular android aguenta rodar pelo termux.
# só lê informação do próprio aparelho. não acessa a rede, não pede root
# e não coleta serial, imei ou conta.
# licença: MIT

set -u

VERSAO="0.2"
DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICOS="$DIR/servicos.tsv"
MEMINFO="${AGUENTA_MEMINFO:-/proc/meminfo}"   # trocável só para teste
RESERVA_MB=300                                 # margem para o android não matar o termux

uso() {
  echo "uso   bash aguenta.sh [--linha]"
  echo "  --linha   imprime só a linha para a tabela de aparelhos"
}

SO_LINHA=0
case "${1:-}" in
  "") ;;
  --linha) SO_LINHA=1 ;;
  -h|--help) uso; exit 0 ;;
  *) uso; exit 1 ;;
esac

if ! command -v getprop >/dev/null 2>&1; then
  echo "aguenta: getprop não encontrado. rode no termux, no android." >&2
  exit 1
fi

prop() { getprop "$1" 2>/dev/null; }
ler() { [ -r "$1" ] && head -n 1 "$1" 2>/dev/null; }
numero() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; }

largura="${AGUENTA_COLUNAS:-$(stty size 2>/dev/null | cut -d' ' -f2)}"   # colunas da tela
numero "$largura" || largura=80

# texto corrido, quebrado na largura da tela
texto() { printf '%s\n' "$1" | fold -s -w "$largura"; }

# rótulo e valor, com o valor quebrado em linhas alinhadas na coluna dada
item() {
  local rotulo=$1 valor=$2 coluna=$3 recuo espaco parte primeira=1
  recuo=$(printf '%*s' "$coluna" '')
  espaco=$(( largura - coluna ))
  [ "$espaco" -lt 16 ] && espaco=16
  while IFS= read -r parte; do
    if [ "$primeira" -eq 1 ]; then
      printf '%s%s%s\n' "$rotulo" "${recuo:${#rotulo}}" "$parte"
      primeira=0
    else
      printf '%s%s\n' "$recuo" "$parte"
    fi
  done < <(printf '%s\n' "$valor" | fold -s -w "$espaco")
}

# ---------- coleta ----------

fabricante=$(prop ro.product.manufacturer)
modelo=$(prop ro.product.model)
# algumas marcas já colocam o nome no modelo (motorola edge, por exemplo)
case "$(echo "$modelo" | tr '[:upper:]' '[:lower:]')" in
  "$(echo "$fabricante" | tr '[:upper:]' '[:lower:]')"*) aparelho="$modelo" ;;
  *) aparelho="$fabricante $modelo" ;;
esac
aparelho=$(echo "$aparelho" | sed 's/^ *//; s/ *$//')
[ -z "$aparelho" ] && aparelho="desconhecido"

android=$(prop ro.build.version.release)
[ -z "$android" ] && android="?"
sdk=$(prop ro.build.version.sdk)
numero "$sdk" || sdk=0

soc=$(prop ro.soc.model)
[ -z "$soc" ] && soc=$(prop ro.board.platform)
[ -z "$soc" ] && soc=$(prop ro.hardware)
[ -z "$soc" ] && soc="desconhecido"

if [ -n "$(prop ro.product.cpu.abilist64)" ]; then
  bits=64
else
  bits=32
fi

nucleos=$(nproc 2>/dev/null)
numero "$nucleos" || nucleos=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)
numero "$nucleos" || nucleos="?"

freq_khz=0
for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq; do
  v=$(ler "$f")
  if numero "$v" && [ "$v" -gt "$freq_khz" ]; then
    freq_khz=$v
  fi
done
if [ "$freq_khz" -gt 0 ]; then
  freq=$(awk -v k="$freq_khz" 'BEGIN { printf "até %.1f ghz", k / 1000000 }')
else
  freq="frequência não disponível"
fi

ram_total=$(awk '/^MemTotal:/ { print int($2 / 1024) }' "$MEMINFO" 2>/dev/null)
ram_livre=$(awk '/^MemAvailable:/ { print int($2 / 1024) }' "$MEMINFO" 2>/dev/null)
numero "$ram_total" || ram_total=0
numero "$ram_livre" || ram_livre=0

# tamanho anunciado do aparelho: o android sempre mostra um pouco menos
classe=0
if [ "$ram_total" -gt 0 ]; then
  for g in 1 2 3 4 6 8 12 16 24; do
    if [ "$ram_total" -le $((g * 1024)) ]; then
      classe=$g
      break
    fi
  done
  [ "$classe" -eq 0 ] && classe=$(( (ram_total + 1023) / 1024 ))
fi

disco=$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 { print int($4 / 1024) }')
numero "$disco" || disco=0
if [ "$disco" -ge 10240 ]; then
  disco_txt="$(( disco / 1024 )) gb livres"
else
  disco_txt="$disco mb livres"
fi

gpu_props=$(echo "$(prop ro.hardware.egl) $(prop ro.hardware.vulkan)" | tr '[:upper:]' '[:lower:]')
case "$gpu_props" in
  *adreno*) gpu="adreno" ;;
  *mali*) gpu="mali" ;;
  *powervr*|*pvr*) gpu="powervr" ;;
  *) gpu="desconhecida" ;;
esac

case "$(prop ro.boot.hypervisor.vm.supported) $(prop ro.boot.hypervisor.protected_vm.supported)" in
  *1*|*true*) avf="sim" ;;
  *) avf="não" ;;
esac

# o termux-battery-status trava se o app termux:api não estiver instalado
saude=""
if command -v termux-battery-status >/dev/null 2>&1; then
  saude=$(timeout 10 termux-battery-status 2>/dev/null \
    | sed -n 's/.*"health": *"\([A-Za-z_]*\)".*/\1/p' | head -n 1)
fi

capacidade=""
for d in /sys/class/power_supply/battery /sys/class/power_supply/bms; do
  cheia=$(ler "$d/charge_full")
  projeto=$(ler "$d/charge_full_design")
  if numero "$cheia" && numero "$projeto" && [ "$projeto" -gt 0 ]; then
    capacidade=$(( cheia * 100 / projeto ))
    break
  fi
done

# ---------- avaliação ----------

if [ "$classe" -eq 0 ]; then
  ambiente="sem leitura de ram"
elif [ "$classe" -le 2 ]; then
  ambiente="só terminal, ambiente gráfico fica lento demais"
elif [ "$classe" -le 3 ]; then
  ambiente="lxqt"
elif [ "$classe" -le 4 ]; then
  ambiente="lxqt ou xfce"
elif [ "$classe" -le 6 ]; then
  ambiente="xfce ou mate"
else
  ambiente="qualquer um, inclusive kde"
fi

case "$gpu" in
  adreno) aceleracao="adreno tem caminho de aceleração no termux:x11 (turnip ou zink), dependendo do modelo" ;;
  *) aceleracao="sem driver aberto no termux. zink sobre o vulkan do android funciona em alguns aparelhos, mas conte com renderização por software" ;;
esac

if [ "$bits" -eq 64 ] && [ "$sdk" -ge 28 ]; then
  if [ "$avf" = "sim" ]; then
    podroid="roda, com avf (perto do nativo)"
  else
    podroid="roda, mas sem avf vai por emulação (lento)"
  fi
else
  podroid="não roda (pede android 9 ou mais novo, em 64 bits)"
fi

if [ -n "$saude" ] && [ -n "$capacidade" ]; then
  bateria_info="saúde $saude, ${capacidade}% da capacidade original"
elif [ -n "$saude" ]; then
  bateria_info="saúde $saude"
elif [ -n "$capacidade" ]; then
  bateria_info="${capacidade}% da capacidade original"
else
  bateria_info="sem leitura"
fi

if [ -z "$saude" ] && [ -z "$capacidade" ]; then
  bateria="sem leitura (instale o pacote termux-api e o app termux:api)"
else
  bateria="ok"
  case "$saude" in
    DEAD|OVERHEAT|OVER_VOLTAGE|UNSPECIFIED_FAILURE) bateria="saúde $saude" ;;
  esac
  if [ -n "$capacidade" ] && [ "$capacidade" -lt 70 ]; then
    bateria="desgastada (${capacidade}% da original)"
  fi
  if [ "$bateria" != "ok" ]; then
    bateria="$bateria. para ficar ligado 24h, é melhor alimentar sem bateria"
  fi
fi

if [ "$disco" -lt 3000 ]; then
  armazenamento="pouco espaço. um debian com ambiente gráfico pelo proot ocupa uns 3 gb ou mais"
else
  armazenamento="ok"
fi

linha="| $aparelho | $soc | $android | $bits | ${classe} gb | $gpu | $avf | (preencha o que rodou bem) |"

# ---------- saída ----------

if [ "$SO_LINHA" -eq 1 ]; then
  echo "$linha"
  exit 0
fi

echo "aguenta $VERSAO"
echo
item "aparelho" "$aparelho" 15
item "soc" "$soc" 15
item "android" "$android (sdk $sdk), $bits bits" 15
[ "$nucleos" = "1" ] && palavra="núcleo" || palavra="núcleos"
item "cpu" "$nucleos $palavra, $freq" 15
item "ram" "$ram_total mb (aparelho de ~$classe gb), $ram_livre mb livres agora" 15
item "armazenamento" "$disco_txt" 15
item "gpu" "$gpu" 15
item "avf" "$avf" 15
item "bateria" "$bateria_info" 15
echo
item "ambiente gráfico" "$ambiente" 18
item "aceleração" "$aceleracao" 18
item "podroid" "$podroid" 18
item "bateria" "$bateria" 18
item "armazenamento" "$armazenamento" 18

if [ -r "$SERVICOS" ]; then
  orcamento=$(( ram_livre - RESERVA_MB ))
  [ "$orcamento" -lt 0 ] && orcamento=0
  echo
  texto "serviços, cada um sozinho, com a ram livre de agora"
  while IFS=$'\t' read -r nome ram root nota; do
    case "$nome" in ''|\#*) continue ;; esac
    if [ "$root" = "sim" ]; then
      estado="precisa de root"
      [ -n "$nota" ] && estado="$estado, porque $nota"
    elif numero "$ram" && [ "$ram" -gt "$orcamento" ]; then
      estado="não cabe agora (~$ram mb)"
      [ -n "$nota" ] && estado="$estado. $nota"
    else
      estado="cabe (~$ram mb)"
      [ -n "$nota" ] && estado="$estado. $nota"
    fi
    item "  $nome" "$estado" 16
  done < "$SERVICOS"
fi

echo
texto "as faixas de ram e o consumo dos serviços são estimativas iniciais."
echo
echo "linha para a tabela de aparelhos"
echo "$linha"
