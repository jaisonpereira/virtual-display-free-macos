# virtual-display-free-macos

Utilitário gratuito e de código aberto para criar uma tela virtual no macOS e
espelhá-la em um monitor externo. Uma área de trabalho virtual de **1920 × 1080**
pode ser reduzida para um painel físico de **1366 × 768**, permitindo acomodar
mais conteúdo com perda de nitidez.

**Sem avaliação, licença paga ou dependência do BetterDisplay. Licença MIT.**

## Instalação

Baixe o ZIP para Apple Silicon e Intel na página de
[Releases](https://github.com/jaisonpereira/virtual-display-free-macos/releases).
Extraia e mova `virtual-display-free-macos.app` para a pasta Aplicativos.

O binário tem assinatura ad hoc, sem notarização da Apple. Dependendo da política
do macOS, o sistema pode bloquear um aplicativo baixado da internet. A alternativa
é compilar o código localmente, conforme abaixo. Não é necessário desativar
proteções do sistema.

## Usar

1. Abra `virtual-display-free-macos.app`.
2. Selecione o monitor externo. Com apenas um monitor externo, ele é selecionado
   inicialmente. A tela integrada não é oferecida como destino.
3. Use 1920 × 1080 ou digite a resolução desejada, até 4096 em cada dimensão.
4. Clique em **Ativar**. O macOS passa a espelhar a tela virtual no monitor escolhido.
5. Clique em **Restaurar** para remover a tela virtual e voltar ao modo anterior.

O ícone **VD** na barra de menus permite reabrir a janela, restaurar o monitor e
sair. Fechar apenas a janela mantém a tela virtual ativa. **Sair** remove a tela
virtual e restaura o monitor. O aplicativo precisa permanecer em execução.

Também é possível criar uma tela virtual sem espelhamento, selecionando essa
opção no monitor de destino. O aplicativo não inicia automaticamente no login e
não ativa uma tela ao ser aberto: a ativação é explícita. Após desconectar um
monitor, use Restaurar, reabra o aplicativo para atualizar os destinos e ative
novamente; esta versão não gerencia reconexão automática.

## Compilar

Requer macOS com Xcode ou Command Line Tools e o compilador Clang.

```bash
./scripts/build.sh
open build/virtual-display-free-macos.app
```

A compilação gera um aplicativo universal (`arm64` + `x86_64`) com versão mínima
de execução macOS 13.0. **Testado no macOS 26.2, Apple M3 Pro, com um LG
20MK400H-B conectado por HDMI.** Outros Macs e versões não foram validados
fisicamente. A criação da tela depende da disponibilidade das APIs internas.

## Linha de comando

```bash
APP="build/virtual-display-free-macos.app/Contents/MacOS/virtual-display-free-macos"
"$APP" --list-displays
"$APP" --headless --width 1920 --height 1080 --mirror ID_DO_MONITOR
```

Substitua `ID_DO_MONITOR` pelo ID retornado pela primeira chamada. IDs de tela
podem mudar. O modo `--headless` omite a interface; ainda requer uma sessão gráfica
ativa do macOS. Para criar somente a tela virtual, omita `--mirror`.
`Ctrl+C` ou `SIGTERM` remove a tela virtual e restaura o destino.

`--list-displays`, `--help` e `--version` são consultas sem alteração de telas.
Uma segunda instância de criação é recusada; as consultas continuam disponíveis.
O programa recusa destinos integrados ou que já participem de espelhamento.

## Testes

```bash
./scripts/build.sh
./scripts/test.sh
```

Os testes acima verificam argumentos, execução do binário e consultas. Não alteram
resoluções. Há um teste de integração opcional, que **altera temporariamente as
telas reais** e verifica criação, resolução, espelhamento, instância única,
remoção e restauração do destino e da tela integrada:

```bash
python3 scripts/integration_test.py ID_DO_MONITOR
python3 scripts/integration_test.py ID_DO_MONITOR --interrupt
```

A primeira chamada testa encerramento temporizado; a segunda testa `SIGTERM`.
Sem ID, o teste cria somente uma tela virtual, sem espelhar.

## Como funciona e limites

- Cria um `CGVirtualDisplay` local e mantém o objeto vivo durante a execução.
- Usa funções públicas do CoreGraphics para espelhar a tela no destino.
- A criação usa classes **privadas e não documentadas pela Apple**, resolvidas
  dinamicamente. Isso não é uma opção nativa dos Ajustes do Sistema e pode deixar
  de funcionar após uma atualização do macOS. Não há garantia de compatibilidade.
- O único modo anunciado é o tamanho escolhido a 60 Hz, sem HiDPI, HDR ou streaming.
- As configurações de espelhamento são aplicadas somente à sessão; o aplicativo
  não grava overrides de EDID nem instala drivers ou helpers privilegiados.
- Ao restaurar, modifica somente a relação de espelhamento que criou. Se outro
  aplicativo mudar o destino, não impõe o modo antigo sobre essa nova configuração.
- Não aumenta a resolução física do painel. Mais espaço significa texto e
  elementos menores e, em monitores de menor resolução, menos nítidos.
- Não usa internet, telemetria, captura de tela ou permissões de gravação de tela.
- O pacote publicado tem assinatura ad hoc; não tem notarização nem assinatura
  Developer ID. O suporte a Intel foi validado por compilação, não em hardware.

Referência para as assinaturas das APIs internas:
[node-mac-virtual-display](https://github.com/enfp-dev-studio/node-mac-virtual-display/blob/main/src/virtual_display.mm).
O código deste utilitário foi implementado independentemente, sem dependência
desse projeto.
