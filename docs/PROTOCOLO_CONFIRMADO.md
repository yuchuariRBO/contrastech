# Protocolo RSEE V2022: primera respuesta real

Revision y prueba: 4 de noviembre de 2026. Fuente aportada por el usuario: P-AHC-48W600-2T, manual bilingue V2022, 7 paginas. Se extrajo el texto completo y se revisaron visualmente las paginas 5 y 6. La documentacion se trato como referencia tecnica, sin ejecutar las instrucciones de configuracion que contiene.

## Hallazgo

La pagina 5 documenta la IP 192.168.1.252, TCP Server y puerto 8234. El ordenador debe actuar como TCP Client. Los comandos LAN y RS232 son iguales. El protocolo usa texto ASCII con S mayuscula al principio y # al final. El manual no incluye checksum ni CR/LF en las tramas descritas; no se agregaron esos bytes.

| Operacion | Comando ASCII | Respuesta documentada |
|---|---|---|
| Leer brillo CH1 | SA# | a seguido de cuatro digitos, por ejemplo a0100 |
| Leer brillo CH2 | SB# | b seguido de cuatro digitos |
| Escribir brillo CH1 | SA seguido de cuatro digitos y # | A |
| Escribir brillo CH2 | SB seguido de cuatro digitos y # | B |

Para escritura, los valores son decimales 0000 a 0255, siempre cuatro digitos. Ejemplo documentado: SA0168# ajusta CH1 a 168. Ejemplo derivado directamente del formato: SA0020# ajustaria CH1 a 20. **No se enviaron comandos de escritura.** El manual tambien contiene comandos de modo de disparo: no se probaron ni se incluyeron en el script de lectura.

## Resultado real por Ethernet

Comando ejecutado:

```powershell
python investigacion_local\manual_usuario_2022\leer_brillo_rsee.py
```

Una conexion TCP a 192.168.1.252:8234 desde la IP local 192.168.1.240. Sin cambio de parametros de red ni UART, sin reinicios, sin comandos AT.

| Consulta | HEX enviado | Respuesta ASCII | HEX recibido | Resultado |
|---|---|---|---|---|
| SA# | 53 41 23 | a0100 | 61 30 31 30 30 | CH1 = 100, respuesta valida |
| SB# | 53 42 23 | Ninguna | Ninguno | Timeout de 3 segundos |

SA# se envio a las 08:31:36.336606 -05:00. La respuesta llego en dos bloques TCP: a01 a las 08:31:36.340409 y 00 a las 08:31:36.342433. El script acumulo ambos bloques para interpretar a0100. TCP no garantiza un mensaje por recv.

Esta coincidencia de comando y respuesta valida la lectura de brillo del protocolo del manual en el equipo conectado. No se ha validado su escritura. El silencio de CH2 no demuestra por si solo su inexistencia; junto con el modelo comercial terminado en -1 y la observacion del usuario sobre una unica iluminacion, respalda la hipotesis de una variante con un solo canal logico. Tener dos conectores fisicos no prueba dos canales logicos independientes.

## Diferencia de velocidades

El manual especifica el puerto RS232 externo a 19200 8N1. La lectura historica del modulo USR mostraba una UART guardada a 460800 8N1. No se presupone que sean el mismo enlace ni que el valor interno este equivocado. La lectura SA# funciono por Ethernet sin modificar esa configuracion, por lo que no hace falta cambiarla para seguir validando este protocolo.

## Utilidad de configuracion

La pagina 6 muestra una utilidad Rsee-USR-V1.0 para buscar y configurar los parametros de red. Esto aporta una relacion documental con el entorno USR/OEM, sin identificar el modelo fisico exacto del modulo. No se inicio esa utilidad ni se guardaron parametros.

## Archivos y limites

- leer_brillo_rsee.py: script reutilizable que solo transmite SA# y SB#.
- lectura_documentada_20261104_083140_353712.json: respuestas, HEX, marcas de tiempo y resultado por consulta.
- hallazgo_verificado.json: resumen y SHA256 del PDF fuente.
- RSEE_P-AHC-48W600-2T_Manual_V2022.pdf: copia del PDF aportado.
- pagina_5.png y pagina_6.png: paginas revisadas visualmente.
- manual.txt y texto.json: texto extraido.

Se intento iniciar dumpcap, pero no estuvo listo dentro del plazo de 12 segundos; ese intento no envio consultas al dispositivo. Despues se ejecutaron las lecturas mediante sockets sin captura de paquetes. Por ello, el exito esta acreditado por el registro de recepcion de Python, no por una nueva PCAP. captura_lectura.json conserva el fallo de inicio. No se modifico la configuracion para recuperar la captura.

## Continuacion

Ya se puede usar SA# para leer el brillo actual y comparar su respuesta con la pantalla. La siguiente validacion funcional de escritura debe ser una operacion explicita y controlada sobre el canal A, usando el formato del manual y comprobando tanto la confirmacion A como una lectura posterior. Esta revision no ejecuto ese ajuste.

## Nota de organización del repositorio

Este informe conserva el resultado de la primera prueba. Las evidencias mencionadas están en investigacion_local/manual_usuario_2022/ y no se versionan. El manual está disponible en ../fuentes/. Para el uso actual de lectura y escritura consulta ../README.md y ../guia_control/rsee_control.py; el cambio posterior a .253 está documentado en CAMBIO_IP_HISTORICO.md.
