# Control desde Postman

El controlador NO recibe HTTP. El puente Python de esta carpeta convierte HTTP local a TCP RSEE.

1. Abrir PowerShell en esta carpeta.
2. Ejecutar `python postman_bridge.py` y dejarlo abierto.
3. En Postman de escritorio: Import -> elegir Postman_Luz_RSEE.postman_collection.json.
4. Ejecutar Leer brillo CH1 (GET). No cambia el valor.
5. Para ajustar, elegir Cambiar brillo CH1 (POST), poner brightness entre 0 y 255 en Body -> raw -> JSON y pulsar Send.

URL: http://127.0.0.1:8765/brightness
Sin autenticacion. Encabezado POST: Content-Type: application/json.

Ejemplo de cuerpo:
```json
{"brightness": 200}
```

Respuesta:
```json
{"channel":"CH1","brightness":200,"controller_ip":"192.168.1.253","verified":true}
```

La respuesta es un ejemplo del resultado esperado. Inicia el puente manualmente; cierra con Ctrl+C en la consola. No inicies una segunda copia en el mismo puerto.

El puente solo escucha en esta PC (127.0.0.1). Si cambia la IP del controlador usar --controller-ip; si cambia la IP Ethernet del PC usar --local-ip. Ejecutar desde el escritorio de Postman; la URL localhost no apunta al equipo si se usa un agente remoto.
