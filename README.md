# polygon_crop_app

Um Programa exemplo demonstrando como recortar polígonos de imagens.

## Recursos utilizados

- No mini_dialog é utilizado o pacote 'Flutter Animation Progress Bar' para criar a barra de progresso.
- No poly_painter são utilizadas as classes Isolate, ReceiverPort e Completer para implementar uma Thread a fim de processar o recorte do polígono.

### Algoritmo

Foi empregado o algoritmo para a ordenação dos pontos de recorte tomando como base o centro das coordenadas. Nessa
versão é apresentada alguns problemas na dinâmica de formação das linhas que formam a imagem a medida de modificamos suas coordenadas.

Também é utilizada a conversão das coordenadas dos pontos de recorte para as coordenadas da imagem para ajustar a posição apresentada na tela em 
relação com o tamanho real da imagem. Esta conversão também ocorre quando mudamos a geometria da imagem ao rotacionar o celular fazendo
com que a imagem se ajuste ao tamanho da tela.

Existe dois call backs para tratar as mensagens durante o processo de recorte e outro para informar a quantidade de pontos de recorte
para propiciar à interface meios de habilitar recursos de recorte e limpeza de pontos.

