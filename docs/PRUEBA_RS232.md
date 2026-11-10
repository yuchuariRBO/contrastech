# Prueba RS232 del 10 de noviembre de 2026

Referencia: `fuentes/RSEE_P-AHC-48W600-2T_Manual_V2022.pdf`, página 5, revisada como texto e imagen. Configuración documentada: 19200 baudios, 8 bits de datos, sin paridad, 1 bit de parada. Comandos ASCII iguales a los de Ethernet, terminados en `#`, sin CR/LF.

Windows detectó un dispositivo FTDI USB VID_0403/PID_6011, serie FTBH21MI, con cuatro interfaces: A/COM8, B/COM4, C/COM5 y D/COM7. Ese identificador no demuestra por sí solo el modelo ni el cableado del adaptador. El usuario autorizó probar los cuatro puertos.

Se abrió cada puerto sin control de flujo, con DTR/RTS desactivados y timeout de lectura de 1500 ms. Se envió únicamente `SA#` durante la identificación:

| Puerto | Respuesta | Resultado |
|---|---|---|
| COM8 | `a0255` | CH1 leído correctamente: 255 |
| COM4 | Ninguna | Timeout |
| COM5 | Ninguna | Timeout |
| COM7 | Ninguna | Timeout |

En COM8 se realizó después esta prueba de escritura y restauración:

| Comando | Respuesta | Interpretación |
|---|---|---|
| `SA#` | `a0255` | Brillo inicial 255 |
| `SA0250#` | `A` | Escritura aceptada |
| `SA#` | `a0250` | Brillo 250 verificado |
| `SA#` | `a0250` | Lectura previa a restauración |
| `SA0255#` | `A` | Restauración aceptada |
| `SA#` | `a0255` | Brillo final 255 verificado |

Pruebas ejecutadas aproximadamente a las 13:30, hora de Ecuador (UTC-05:00), con `guia_control/rsee_serial.ps1`. Las seis ejecuciones guardaron registros locales `guia_control/operation_serial_20261110_*.json`, excluidos de Git.

## Pruebas posteriores de la misma sesión

Todas las horas corresponden a Ecuador (UTC-05:00), el 10/11/2026.

| Hora aproximada | Operación | Resultado observado |
|---|---|---|
| 13:31 | CH1 a 125 y luego a 200 | Acuses `A`, lecturas `a0125` y `a0200` |
| 13:32 | Lectura de CH2: `SB#` | Timeout sin respuesta; no se escribió CH2 |
| 13:32 | Nueva lectura de CH1 | `a0200`; comunicación CH1 operativa |
| 13:35 | High: `SH#` | Acuse `H` |
| 13:54 | CH1 a 200 | Acuse `A` y lectura `a0200` |
| 13:54 | Subida/bajada CH1 | 225, 250, 225, 200, 175, 150, 175, 200; cada valor con acuse y lectura coincidente |
| 13:55 | Low: `SL#` | Acuse `L` |
| 15:32 | Lectura CH1 con la versión final del script | `a0129`; brillo leído 129, sin escrituras |

Las operaciones de modo se ejecutaron inicialmente mediante `System.IO.Ports.SerialPort` directamente y guardaron `operation_serial_mode_*.json`. Posteriormente se incorporaron las acciones `high` y `low` al script reutilizable. La subida/bajada real se hizo con una secuencia de invocaciones `set`; las nuevas acciones `ramp` y `demo` se comprobaron con el simulador, sin ejecutar otro ciclo físico durante la preparación de esta documentación.

La secuencia de control terminó con CH1 = 200 y el último cambio de modo recibió acuse Low. Durante la verificación posterior del script, a las 15:32, CH1 respondió 129. No se identificó la causa del cambio entre ambas lecturas y no se intentó restaurar 200: la verificación final fue exclusivamente de lectura. No se consultó el modo porque el manual no documenta una consulta independiente. Estos valores son referencias históricas, no una consulta en vivo.

La sesión confirma lectura y escritura de CH1 mediante COM8 y aceptación de los comandos High/Low. CH2 se consultó pero no respondió. No se comprobó persistencia tras apagar, el cambio óptico mediante medición o confirmación visual, ni la respuesta física a una señal externa de disparo. No se cambió la configuración de red.

Los registros originales quedan locales y excluidos de Git. Para repetir las operaciones, consultar [CONTROL_RS232.md](../guia_control/CONTROL_RS232.md).
