# Control del RSEE por USB / RS232

Esta guía corresponde al controlador conectado a esta PC y al protocolo de la página 5 de `fuentes/RSEE_P-AHC-48W600-2T_Manual_V2022.pdf`. La herramienta es `rsee_serial.ps1`, para Windows PowerShell 5.1 (`powershell.exe`), sin instalar Python ni paquetes externos.

## Conexión comprobada

| Ajuste | Valor |
|---|---|
| Puerto que respondió el 10/11/2026 | COM8 |
| Velocidad | 19200 baudios |
| Datos / paridad / parada | 8 / ninguna / 1 (8N1) |
| Control de flujo | Ninguno; DTR y RTS desactivados |
| Codificación | ASCII |
| Fin de comando | `#`, sin CR ni LF |
| Tiempo de espera predeterminado | 1500 ms por respuesta |
| Brillo | Entero entre 0 y 255; se envía con cuatro dígitos |

CH1 respondió a lecturas y escrituras. CH2 está descrito en el manual, pero `SB#` no respondió en este equipo. La herramienta admite ambos canales y exige una lectura inicial válida antes de escribir: si CH2 sigue sin responder, no enviará la escritura.

El FTDI conectado presenta COM8, COM4, COM5 y COM7. Las letras A/B/C/D de las interfaces USB del FTDI identifican puertos físicos del adaptador; no corresponden a CH1/CH2 del RSEE. Ambos canales RSEE se direccionan por comandos a través de la misma conexión COM8. Un timeout no demuestra por sí solo que CH2 esté averiado o que no exista.

Para listar los puertos actuales sin enviar comandos:

```powershell
[System.IO.Ports.SerialPort]::GetPortNames()
Get-PnpDevice -PresentOnly -Class Ports | Select-Object Status,FriendlyName,InstanceId
```

Los números COM pueden cambiar al reconectar el USB. Cierra otro programa que pueda tener abierto el mismo puerto. El adaptador debe proporcionar niveles eléctricos RS232 adecuados para el controlador; un UART TTL no equivale a RS232. El dibujo del conector está en la página 5 del manual.

## Brillo y High/Low son ajustes distintos

El brillo fija el nivel de iluminación de cada canal. High/Low selecciona el comportamiento frente a la entrada externa de disparo. En el protocolo documentado, los comandos de modo no incluyen dirección de canal y se tratan como ajustes del controlador.

| Modo | Sin señal externa | Con señal externa activa |
|---|---|---|
| High (`SH#`) | Luz encendida | Luz apagada |
| Low (`SL#`) | Luz apagada | Luz encendida mientras dure la señal alta |

High no significa brillo máximo. Low no significa brillo mínimo. Un brillo de 200 puede seguir guardado aunque la luz esté apagada en Low por ausencia de disparo. Cambiar brillo no envía comandos High/Low; cambiar modo no envía un valor de brillo.

No hay un comando de consulta de modo documentado en este manual. La herramienta informa el acuse recibido al cambiarlo; no inventa una lectura independiente del estado. El control óptico del disparo y su temporización no se midieron durante estas pruebas.

## Comandos listos para ejecutar

Abre PowerShell en la raíz del repositorio `contrastech`. Cada ejemplo es independiente: ejecuta únicamente el que corresponda a la operación deseada. `-ExecutionPolicy Bypass` se aplica al proceso lanzado; no cambia permanentemente la política del equipo.

### Encendido sin disparo: High

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action high
```

Envía `SH#`, exige respuesta `H`. No se debe añadir `-Channel`.

### Encendido mediante disparo: Low

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action low
```

Envía `SL#`, exige respuesta `L`. No se debe añadir `-Channel`.

### Leer el brillo sin cambiarlo

```powershell
# CH1, confirmado en el equipo
powershell.exe -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action read -Channel A

# CH2, según manual; en la prueba real no respondió
powershell.exe -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action read -Channel B
```

### Ajustar el brillo de un canal

```powershell
# CH1 a 200/255
powershell.exe -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action set -Channel A -Value 200

# CH2 a 125/255: se ejecuta solo si su lectura inicial responde
powershell.exe -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action set -Channel B -Value 125
```

La secuencia es lectura inicial, escritura, acuse y lectura posterior. Un acuse sin lectura coincidente no cuenta como ajuste verificado. Cada canal se controla por separado; no existe una operación simultánea o atómica en esta herramienta. El canal predeterminado es A/CH1. No hay un comando independiente para seleccionar el canal mostrado en el panel en el protocolo descrito.

### Rampa hasta un valor

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action ramp -Channel A -Value 100 -Step 10 -IntervalMs 200
```

Lee el valor inicial y sube o baja en pasos de hasta 10 hasta llegar exactamente a 100. Verifica cada paso y deja aplicado el objetivo. `IntervalMs` es una pausa adicional después de cada paso, no un período de tiempo real garantizado; a ella se suma el tiempo de comunicación y verificación.

### Subir y bajar, regresando al valor inicial

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action demo -Channel A -Minimum 150 -Maximum 250 -Step 25 -IntervalMs 500
```

Hace un ciclo: valor inicial → máximo → mínimo → valor inicial. Si empieza en 200, verifica esta secuencia: `225, 250, 225, 200, 175, 150, 175, 200`. Los límites describen los objetivos del ciclo; si el valor inicial está fuera de ese intervalo, la salida y el regreso también pasan por valores externos al intervalo.

La demostración termina después de un ciclo. No modifica el modo de disparo: para verla sin señal externa, el controlador debe estar en High. Si ocurre un error o se interrumpe con Ctrl+C, puede quedar aplicado el último valor enviado; no se intenta restaurarlo automáticamente tras un fallo.

### Usar las operaciones desde otro script

Ejemplo completo para dejar High y CH1 en 200; si falla el cambio de modo, no continúa con el brillo:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action high
if ($LASTEXITCODE -ne 0) { throw 'No se confirmó High; secuencia detenida.' }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action set -Channel A -Value 200
if ($LASTEXITCODE -ne 0) { throw 'No se verificó el brillo; consultar antes de reintentar.' }
```

## Parámetros

| Parámetro | Uso / predeterminado |
|---|---|
| `-Port` | Obligatorio, por ejemplo `COM8` |
| `-Action` | `read`, `set`, `high`, `low`, `ramp`, `demo`; predeterminado `read` |
| `-Channel` | `A` = CH1, `B` = CH2; predeterminado A; no se admite con High/Low |
| `-Value` | Obligatorio para `set` y `ramp`; entero 0..255 |
| `-Step` | Solo `ramp`/`demo`; 1..255; predeterminado 10 |
| `-IntervalMs` | Solo `ramp`/`demo`; 50..10000 ms; predeterminado 300 |
| `-Minimum` | Solo `demo`; 0..255; predeterminado 150 |
| `-Maximum` | Solo `demo`; 0..255 y mayor que Minimum; predeterminado 250 |
| `-TimeoutMs` | 100..10000 ms; predeterminado 1500 |
| `-Log` | Ruta de JSON; la carpeta padre debe existir |

Ayuda integrada: `Get-Help .\guia_control\rsee_serial.ps1 -Full`.

## Protocolo para integrar en otros programas

| Operación | Bytes ASCII enviados | Respuesta esperada |
|---|---|---|
| Leer CH1 | `SA#` | `a` + cuatro dígitos, ejemplo `a0200` |
| Leer CH2 | `SB#` | `b` + cuatro dígitos, ejemplo `b0125` |
| Escribir CH1 a 200 | `SA0200#` | `A` |
| Escribir CH2 a 125 | `SB0125#` | `B` |
| High | `SH#` | `H` |
| Low | `SL#` | `L` |

Ejemplos de lectura y escritura CH2 provienen del manual; no son respuestas observadas en este equipo. Se distinguen mayúsculas y minúsculas. No se agrega checksum, espacio, CR ni LF. Una lectura son cinco caracteres y los acuses son uno. La respuesta puede llegar fragmentada: el script acumula los caracteres dentro de un plazo total por respuesta. No se debe abrir el mismo puerto desde dos clientes a la vez.

## Resultados, errores y registros

El script imprime un JSON y devuelve código de salida 0 al completar con éxito, 1 si falla una operación de comunicación o verificación. Los parámetros inválidos producen un error antes de abrir el puerto.

Cada operación terminada normalmente, incluida una que captura un fallo de comunicación, genera `guia_control/operation_serial_*.json`, excluido de Git. El registro contiene fecha con zona horaria, puerto, acción, canal cuando aplica, tramas `tx`/`rx` y `success`. Las escrituras registran los pasos verificados; `final_brightness` aparece al terminar correctamente y `last_verified_brightness` conserva la última lectura validada. Tras un error, este último dato es histórico: una escritura posterior a esa lectura pudo haberse aplicado aunque su respuesta fallara. En High/Low se registra `mode_acknowledged`, sin afirmar una lectura de modo. Una interrupción forzada o un error de validación puede no generar archivo.

| Síntoma | Comprobación |
|---|---|
| Puerto no existe o acceso denegado | Revisar puertos y cerrar otros programas que lo usen |
| Timeout sin respuesta | Revisar COM, alimentación, conexión RS232 y parámetros; se usó COM8/19200 8N1 |
| CH1 responde y CH2 no | Es el resultado observado; no enviar escrituras ciegas ni cambiar de COM suponiendo que representa CH2 |
| Acuse inesperado o lectura distinta | La herramienta se detiene sin reintentos; leer de nuevo antes de otra escritura |
| Brillo leído correctamente pero luz apagada | Comprobar modo Low y señal externa; brillo y modo son ajustes distintos |
| Falla al guardar JSON | Revisar permisos/ruta; el comando físico pudo haberse ejecutado antes del fallo de registro |

## Verificación del código

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File guia_control/test_rsee_serial.ps1
```

Estas pruebas sustituyen el puerto por un dispositivo simulado: comprueban tramas de CH1/CH2, High/Low, rampas, retorno de la demostración, rechazo de parámetros y detención ante timeout, acuse inválido o lectura discordante. No abren puertos reales ni certifican el hardware CH2.

Las pruebas reales y sus límites están en [PRUEBA_RS232.md](../docs/PRUEBA_RS232.md). El puente Postman existente utiliza Ethernet y CH1; no ejecuta este script RS232 ni ofrece High/Low. Las herramientas Ethernet anteriores continúan descritas en el [README](../README.md).
