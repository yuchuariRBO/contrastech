# Constratech / RSEE

Herramientas Python para controlar el brillo CH1 por Ethernet en el controlador CONTRASTECH/RSEE estudiado. Incluye lectura, ajuste con verificación, rampas, puente HTTP local para Postman y respaldo/cambio de IP del módulo USR.

## Instalación

Se requiere Python 3. Las herramientas utilizan únicamente la biblioteca estándar; no hay paquetes externos que instalar. El cambio de IP utiliza `SendARP` de Windows. Para los comandos de brillo se necesita acceso TCP al equipo y una IP local configurada en su subred.

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
```

Las comprobaciones de preparación del repositorio no operan el equipo. Los resultados de hardware descritos en los documentos son históricos; no acreditan el estado actual ni la persistencia del brillo después de apagar el controlador.
