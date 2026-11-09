# Cambio de IP completado

192.168.1.252 -> **192.168.1.253**. Puerto TCP: **8234**.

Confirmado por descubrimiento de la misma MAC y lectura SA# -> a0125 desde la nueva direccion. Brillo final: **125**.

Se respaldo la configuracion y se modifico unicamente el byte de IP que paso de 252 a 253. Los otros 129 bytes de la configuracion principal coinciden con el respaldo, tambien despues del reinicio del modulo Ethernet necesario para aplicar el cambio. No se restablecieron valores de fabrica.

Mascara: 255.255.255.0. Gateway: 192.168.1.1. UART guardada: 460800 8N1.
