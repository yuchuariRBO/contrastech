# Constratech / RSEE

Herramientas para controlar el controlador CONTRASTECH/RSEE por USB/RS232 con PowerShell y por Ethernet con Python. Incluye brillo con verificación, modos High/Low por RS232, rampas, demostración de subida/bajada, puente HTTP local para CH1 por Ethernet y respaldo/cambio de IP del módulo USR. CH1 se confirmó en el equipo; CH2 está implementado según el manual, pero no respondió en la prueba real.

Para la conexión USB actual, empieza por la [guía completa de control RS232](guia_control/CONTROL_RS232.md).

## Instalación

RS232 requiere Windows PowerShell 5.1 y un adaptador USB-RS232 con su controlador instalado; no requiere Python. Las herramientas Ethernet requieren Python 3 y utilizan únicamente la biblioteca estándar; no hay paquetes externos que instalar. El cambio de IP utiliza `SendARP` de Windows. Para los comandos Ethernet se necesita acceso TCP al equipo y una IP local configurada en su subred.

```powershell
git clone git@github.com:yuchuariRBO/contrastech.git
cd contrastech
python -m venv .venv
```

Los ejemplos siguientes usan `python` del sistema; puedes sustituirlo por `.venv\Scripts\python.exe`.

## Red y protocolo comprobados

| Parámetro | Valor del equipo estudiado |
|---|---|
| IP del controlador | `192.168.1.253` |
| Puerto TCP | `8234` |
| IP local usada en las pruebas | `192.168.1.240` |
| Lectura CH1 | `SA#` → `a` y cuatro dígitos |
| Escritura CH1 | `SA0000#` … `SA0255#` → `A`, seguida de lectura de verificación |

Son valores históricos de ese equipo; comprueba la red actual antes de ejecutar. Los scripts no configuran la IP de tu PC. Ajusta `--host` y `--local-ip` según tu instalación. La documentación inicial menciona `.252`: posteriormente el equipo pasó a `.253`. No se ha confirmado control independiente de CH2.

## Leer y ajustar el brillo

Leer sin cambiar el brillo:

```powershell
python guia_control/rsee_control.py --host 192.168.1.253 --local-ip 192.168.1.240 read
```

Ajustar CH1 a 125 y comprobarlo mediante lectura:

```powershell
python guia_control/rsee_control.py --host 192.168.1.253 --local-ip 192.168.1.240 set 125
```

Aplicar una rampa hasta 200:

```powershell
python guia_control/rsee_control.py --host 192.168.1.253 --local-ip 192.168.1.240 ramp 200 --step 5 --interval 0.2
```

`set`, `ramp` y `random-demo` modifican la iluminación real. Los valores admitidos son enteros entre 0 y 255. Cada operación genera un JSON local `operation_*.json`, excluido de Git; `--log` permite elegir otra ruta. Ante un error, el programa se detiene sin reintentar la escritura. Una interrupción de la demostración puede dejar el último brillo aplicado.

## Control RS232 por USB en Windows

`guia_control/rsee_serial.ps1` utiliza la biblioteca serie de Windows, sin paquetes adicionales. Configura el adaptador a **19200 8N1**, sin control de flujo, y transmite ASCII sin CR/LF, según la página 5 del manual V2022.

El 10 de noviembre de 2026 se confirmó CH1 por **COM8**: lectura inicial 255, ajuste a 250 y restauración a 255, ambos con acuse `A` y lectura de verificación. COM4, COM5 y COM7 no respondieron a `SA#` durante esa prueba. Los números COM pueden cambiar al reconectar el adaptador.

Desde la raíz del repositorio, consultar sin cambiar la iluminación:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action read
```

Ajustar CH1 y verificar el valor leído:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action set -Value 125
```

Cambiar modo High/Low (ajuste del controlador, sin `-Channel`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action high
powershell -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action low
```

Cada línea cambia el modo: ejecuta la que necesites. High enciende sin señal de disparo y apaga con señal; Low apaga sin señal y enciende mientras la señal esté activa. No equivalen a brillo máximo/mínimo.

Rampa y demostración de un ciclo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action ramp -Channel A -Value 100 -Step 10 -IntervalMs 200
powershell -NoProfile -ExecutionPolicy Bypass -File guia_control/rsee_serial.ps1 -Port COM8 -Action demo -Channel A -Minimum 150 -Maximum 250 -Step 25 -IntervalMs 500
```

`set` y `ramp` modifican la iluminación real y dejan el objetivo aplicado; `demo` regresa al valor inicial si termina correctamente. El script lee antes de escribir brillo y comprueba el acuse y la lectura posterior; ante un fallo se detiene sin reintentar ni restaurar automáticamente. High/Low se comprueban por acuse, sin consulta independiente del modo. Las operaciones guardan las tramas y el resultado en `guia_control/operation_serial_*.json`, excluido de Git. `-Log` permite elegir el archivo. Una interrupción puede dejar el último ajuste aplicado y no guardar el registro.

`-Channel B` dirige las operaciones de brillo a CH2 según el manual; su lectura se intentó sin respuesta. Si falla esa lectura inicial, no se escribe el canal. Las acciones de brillo no cambian el modo de disparo. No se modifica la configuración Ethernet. [Guía, protocolo y solución de problemas](guia_control/CONTROL_RS232.md). [Evidencia de la prueba RS232](docs/PRUEBA_RS232.md).

## Postman

```powershell
python guia_control/postman_bridge.py --controller-ip 192.168.1.253 --local-ip 192.168.1.240
```

Importa `guia_control/Postman_Luz_RSEE.postman_collection.json` en Postman de escritorio.

- `GET http://127.0.0.1:8765/brightness`: consulta el brillo.
- `POST http://127.0.0.1:8765/brightness` con JSON `{"brightness": 125}`: cambia y verifica el brillo.

El puente escucha en `127.0.0.1`, sin autenticación. Déjalo abierto en la consola y ciérralo con Ctrl+C. [Instrucciones de Postman](guia_control/POSTMAN_LEER_PRIMERO.md).

## Respaldo y cambio de IP

`guia_control/rsee_ip.py` solicita la contraseña USR de forma interactiva. La contraseña del equipo no está incluida. Requiere la MAC y el usuario correctos; los valores predeterminados corresponden al equipo estudiado.

Respaldo y lectura sin cambiar la IP:

```powershell
python guia_control/rsee_ip.py --current-ip 192.168.1.253 --local-ip 192.168.1.240 --mac 38:f4:06:0e:56:93 --username rsee
```

Para cambiarla, añade `--new-ip DIRECCION --apply` con una dirección libre de la misma subred. Esta operación escribe configuración y reinicia el módulo Ethernet; el script respalda y comprueba los datos antes y después. Sin `--apply` no envía la escritura. Los respaldos `ip_backup_*/` quedan fuera de Git y pueden contener datos de configuración privados.

## Archivos y documentación

- `guia_control/`: herramientas reutilizables y colección Postman.
- [Protocolo confirmado](docs/PROTOCOLO_CONFIRMADO.md): primera lectura validada; conserva el contexto y los límites de esa fecha.
- [Cambio de IP histórico](docs/CAMBIO_IP_HISTORICO.md): paso de `.252` a `.253`.
- `fuentes/`: manual RSEE V2022 y manual del módulo USR utilizados como referencia. Los documentos pertenecen a sus respectivos autores; su inclusión no concede una licencia sobre ellos.

La carpeta local `investigacion_local/` conserva los experimentos originales, capturas, herramientas descargadas, respaldos y evidencias. Está excluida de Git; las referencias históricas de los documentos a esas evidencias no están disponibles en un clon nuevo. Latinium y las pruebas HSV pertenecen a proyectos separados.

## Verificación

Se pueden comprobar la sintaxis y las opciones sin conectar el controlador:

```powershell
python -m compileall -q guia_control
python guia_control/rsee_control.py --help
python guia_control/rsee_ip.py --help
python guia_control/postman_bridge.py --help
powershell -NoProfile -ExecutionPolicy Bypass -File guia_control/test_rsee_serial.ps1
```

Las comprobaciones anteriores no operan el equipo; las pruebas RS232 utilizan un dispositivo simulado. Los resultados de hardware descritos en los documentos son históricos; no acreditan el estado actual ni la persistencia del brillo después de apagar el controlador.
