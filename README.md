# aguenta

Script para Termux que lê o celular e diz o que ele aguenta rodar, como ambiente gráfico, Podroid e serviços de self-host.

## Rodando

```
pkg install git
git clone https://github.com/umask0ee/aguenta
cd aguenta
bash aguenta.sh
```

Para ler a saúde da bateria, instale também o pacote `termux-api` e o app Termux:API. Sem eles, o script pula essa parte.

`bash aguenta.sh --linha` imprime só a linha para a tabela de aparelhos.

## O que ele lê

Modelo, SoC, versão do Android, se o Android é 64 bits, núcleos e frequência da CPU, RAM, espaço livre, família da GPU, suporte a AVF e, quando disponível, saúde e capacidade da bateria.

## O que ele não faz

Não acessa a rede, não pede root e não coleta serial, IMEI, conta ou qualquer coisa que identifique a pessoa. São cerca de 270 linhas, dá para ler antes de rodar.

## Limites

As faixas de RAM para cada ambiente gráfico e o consumo dos serviços em `servicos.tsv` são estimativas iniciais. Vou ajustando conforme os resultados entrarem na tabela de aparelhos.

A conta dos serviços considera cada um rodando sozinho, com a RAM livre no momento. Para rodar vários, some o consumo.

## Contribuindo com a tabela

Rode o script, copie a linha do final, troque o último campo pelo que rodou bem no seu aparelho e mande no tópico do projeto ou abra um pull request em `aparelhos.md`.

Para corrigir o consumo de um serviço, mande a medição e como ela foi feita.

## Próximos passos

- Teste térmico curto, para ver quanto a CPU cai de frequência sob carga.
- Saída num formato que instaladores como o linux-android possam ler antes de oferecer o menu de ambientes.
- Mais serviços em `servicos.tsv`, com consumo medido.

## Licença

MIT.
