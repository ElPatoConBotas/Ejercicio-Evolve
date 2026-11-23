#!/bin/bash

#Consultar el canal cada 5 segundos y quedarse con el último informe de cada host (group_by(.datos.host) y last).w

while true; do
        clear
        echo "Consultando a las $(date +%H:%M:%S) ..."
        json=$
        curl -s http://62.238.114.81:8089/sync

#Dibujar una tabla en la terminal (clear o tput cup 0 0) con host, CPU, memoria, disco raíz, carga y hora del último informe.


#Marcar como CAÍDO un host cuyo último informe tenga más de 30 segundos.




        sleep 5
done
