# Hoja de ruta (Roadmap)

[Português](ROADMAP.md) · [English](ROADMAP.en.md) · **Español (Honduras)**

Este documento muestra hacia dónde puede ir el proyecto y qué hemos aprendido hasta ahora. Nada de lo que sigue es una promesa de fecha: son intenciones, en orden aproximado de prioridad. Las sugerencias son bienvenidas mediante un *issue*.

## Corto plazo

**Panel**

- **Proteger o eliminar el endpoint de diagnóstico.** `api_ativos.php?debug=1` muestra la estructura de campos de GLPI y no exige autenticación. Restringirlo por IP en el servidor web o desactivarlo en producción.
- **Sacar la lista de SSD del HTML.** Hoy `SSD_EXPANSION_LIST` es una lista de hostnames dentro de la página. Moverla a un archivo de configuración y, mejor aún, leer el tipo de almacenamiento (HDD/SSD) directamente del inventario de GLPI.
- **Reglas de clasificación configurables.** El límite de RAM, las generaciones de CPU consideradas "OK/Atención/Obsoleto" y los tipos de servidor en un archivo de configuración, en lugar de constantes en el código.
- **Modo demostración.** Un conjunto de datos ficticios para probar el panel sin un GLPI y para generar las capturas de pantalla del README.
- **Pruebas automatizadas** para la clasificación por CPU, la alerta de RAM y la normalización del campo "Responsable", usando datos de ejemplo.
- **Restringir el cliente de API por IP** en GLPI, dejando autorizado solo al servidor del panel.
- **Ajustar `cache_ttl_seconds`** según el uso real (hoy 15 minutos).

**Calidad de los datos en GLPI** (el panel solo muestra lo que está registrado; la corrección va en el origen)

- Completar el Estado y el Tipo de los monitores, que llegan vacíos.
- Registrar los celulares (el código ya maneja la lista vacía sin errores).
- Volver obligatorio el campo Grupo en el registro.
- Usar un número de inventario o patrimonio estructurado, en lugar de texto libre en los comentarios.
- Registrar la fecha de adquisición y la garantía en la pestaña financiera.
- Crear una rutina periódica de auditoría de hostnames duplicados y de activos sin responsable.

**GPO del agente**

- **Parametrizar los scripts.** Versión objetivo, servidor y carpeta de red en un archivo de configuración junto al script, en lugar de editar el código en cada actualización.
- **Dar seguimiento a los registros** después de cada despliegue e investigar los agentes que pasan días sin contacto o siguen en versiones antiguas.
- **Reconfirmar el ícono de la bandeja** con cada versión nueva del agente, mediante la prueba manual descrita en [`docs/gpo-glpi-agent.md`](docs/gpo-glpi-agent.md), antes de pasar a producción.
- **Limpiar los scripts heredados** que ya no se usan de la carpeta de red.
- **Documentar qué cuenta** tiene permiso de escritura en la carpeta compartida, para que las actualizaciones no choquen con el bloqueo de permisos.

## Largo plazo

- **Autenticación opcional por departamento**, integrada con el directorio (LDAP/Active Directory) en lugar de contraseñas locales: cada jefe ve solo su área, y TI ve todo. Se hizo una primera versión con contraseñas locales y luego se descartó por simplicidad.
- **Apoyo directo al presupuesto.** Exportar la vista filtrada (CSV/Excel), proyectar cuántos equipos necesitan reemplazo por año y por departamento, y estimar los costos.
- **Clasificación más allá de la CPU:** antigüedad del equipo, garantía y tipo de almacenamiento.
- **Historial y tendencia.** Guardar fotografías periódicas del parque para mostrar su evolución (por ejemplo, el porcentaje de equipos obsoletos a lo largo del tiempo).
- **Alertas** para TI cuando aparezca un activo obsoleto, un hostname duplicado o un agente sin contacto durante varios días.
- **Más tipos de activo:** impresoras, equipos de red y otros itemtypes de GLPI.
- **Interfaz en varios idiomas.** Hoy la documentación principal es trilingüe, pero los textos del panel están en portugués. Mover los textos a un archivo de idiomas.
- **Empaquetado** en contenedor, para una instalación y una demostración más rápidas.
- **Alternativas a la GPO** para desplegar el agente (por ejemplo, administradores de endpoints) y soporte para estaciones que no son Windows.
- **Traducir la carpeta `docs/`** al inglés y al español de Honduras.

## Lecciones aprendidas

1. **Valide el primer dato real, no solo la ausencia de errores.** GLPI guarda la memoria en MB y la regla del panel esperaba GB. Nada falló: todos los equipos simplemente habrían parecido "sin necesidad de mejora de RAM". Solo revisar la primera respuesta real reveló el problema.
2. **Los campos de GLPI varían entre instalaciones.** Los uids de la búsqueda son compuestos (`Computer.<Tipo>.<campo>`) y difieren de lo que sugiere la documentación. Descubrir los campos de forma dinámica y contar con un modo de diagnóstico (`?debug=1`) ahorró mucho tiempo.
3. **Entienda la causa raíz, no solo el síntoma.** El ícono de la bandeja del agente no aparecía al instalar por GPO. Leer las tablas internas del `.msi` mostró que el componente solo se instala en una instalación nueva con `AGENTMONITOR=1` **y** `EXECMODE=1`; reparar o reinstalar funciones no lo resuelve, pero una *actualización* de versión mayor sí.
4. **No todo "error" es un error.** El ícono que "desapareció" horas después de instalar era solo un inicio automático que aún no se había disparado, porque faltaba una sesión nueva. Revisar eso primero evita investigaciones innecesarias.
5. **Sea idempotente y cortés con el servidor.** Un candado (mutex), una espera aleatoria antes de actuar y un intervalo mínimo entre inventarios evitaron instalaciones duplicadas y una avalancha de equipos golpeando GLPI al mismo tiempo.
6. **Asegúrese de que los errores se vean.** En los scripts, usar `-ErrorAction Stop` dentro de `try/catch` hace que el error de "acceso denegado" caiga en el registro en lugar de desaparecer en silencio cuando el script corre sin nadie mirando.
7. **Nunca modifique producción para probar.** El panel tuvo su propio directorio y su propio vhost; el vhost de GLPI nunca se tocó. Siempre `nginx -t` antes de `reload` (nunca `restart`), y un piloto con una GPO aislada antes del despliegue completo.
8. **Los permisos de archivos son una fuente constante de errores.** Un archivo copiado como root después del `chown` vuelve a quedar como `root:root` y PHP-FPM no puede leerlo (HTTP 500). Vuelva a aplicar dueño y permisos después de cada envío.
9. **Verifique que la actualización realmente llegó.** Un `grep` de un fragmento exclusivo de la versión nueva, más el tamaño del archivo, detecta la carga que no sobrescribió o la copia vieja reenviada por error.
10. **Un certificado válido no exige abrirse a internet.** Pasar el panel por un proxy inverso que solo atiende direcciones privadas dio HTTPS sin advertencias sin exponer datos, lo cual importa porque el panel no tiene inicio de sesión.
11. **El panel muestra los problemas, pero la corrección va en el origen.** Los hostnames duplicados, los grupos vacíos y los activos sin responsable aparecen en los indicadores de calidad, y solo corregir el registro en GLPI los resuelve de verdad.
12. **Los cambios de alcance son parte del trabajo.** El inicio de sesión por departamento se implementó y luego se canceló a pedido de la gerencia. Dejarlo detrás de un interruptor de configuración hizo barato el cambio, y después el código muerto se retiró del paquete publicado.
13. **Documente mientras trabaja.** Los registros de decisiones, errores y pruebas fueron lo que permitió retomar el trabajo y, ahora, publicarlo.
