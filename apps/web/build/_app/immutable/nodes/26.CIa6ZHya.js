import{I as e,N as t,P as n,Y as r,bt as i,et as a,gt as o,ht as s,nt as c,s as l,yt as u}from"../chunks/BYdMN7ig.js";import"../chunks/xihTtKlq.js";import"../chunks/DS_t55_M.js";import{n as d}from"../chunks/jftPeae2.js";var f=e(`<article class="doc-page svelte-37b9k6"><h1 class="svelte-37b9k6"><span class="doc-icon svelte-37b9k6"> </span> </h1> <section class="svelte-37b9k6"><h2 id="usuarios-roles" class="svelte-37b9k6">Usuarios y roles</h2> <p class="svelte-37b9k6">En <strong>Configuración → Usuarios</strong> se crean las cuentas del personal: usuario,
      nombre completo, correo, contraseña y el rol que va a tener. Desde ahí también se edita
      el nombre/correo de un usuario existente o se le asigna una nueva contraseña, sin tocar
      su nombre de usuario.</p> <p class="svelte-37b9k6">Cada usuario tiene un estado: <strong>Activo</strong> (puede iniciar sesión), <strong>Inactivo</strong> (se le bloquea el acceso temporalmente, por ejemplo mientras
      está de vacaciones, pero se conserva para reactivarlo después) o <strong>Archivado</strong> (para cuentas que ya no se van a usar; se puede restaurar
      desde el filtro "Archivados" si hiciera falta). Archivar o inactivar nunca borra el
      historial de turnos que ese usuario atendió.</p> <p class="svelte-37b9k6">En <strong>Configuración → Roles</strong> se administran los roles que se pueden asignar
      a un usuario. El sistema ya trae roles con permisos predefinidos (quién ve Recepción,
      Ventanilla, Reportes, el Panel, etc.). Puede crear roles adicionales para organizar a su
      personal, pero tenga en cuenta que un rol nuevo por sí solo no desbloquea automáticamente
      una pantalla que no tenía antes — si necesita que un rol nuevo dé acceso a alguna sección
      específica, consúltelo con soporte técnico.</p></section> <section class="svelte-37b9k6"><h2 id="estaciones-kioscos-areas" class="svelte-37b9k6">Estaciones, kioscos y áreas de servicio</h2> <p class="svelte-37b9k6">Una <strong>estación</strong> (Configuración → Estaciones) es un punto físico de
      atención — un consultorio, una ventanilla — asociado a un área de servicio. Desde ahí se
      crea, se le pone nombre y área, y con el botón <strong>👥 Operadores</strong> se decide
      qué usuarios pueden llamar y atender turnos desde esa estación en particular; un usuario
      solo puede operar las estaciones donde fue asignado explícitamente.</p> <p class="svelte-37b9k6">Un <strong>kiosco</strong> (Configuración → Kioscos) es una terminal de autoservicio para
      pacientes. Cada kiosco inicia sesión con una cuenta de sistema propia (creada en
      Usuarios) y, con el botón <strong>📋 Áreas</strong>, se define a cuáles áreas de servicio
      puede emitir turnos — nunca a las áreas marcadas como prioridad, que solo se emiten desde <a href="/docs/recepcion" class="svelte-37b9k6">Recepción</a>. Vea también <a href="/docs/pantallas-kiosco" class="svelte-37b9k6">Pantallas y Kiosco</a> para el lado del paciente.</p> <p class="svelte-37b9k6">Las áreas de servicio en sí (Consulta, Laboratorio, Imágenes, etc.) se configuran en <strong>Configuración → Prefijos de Módulo</strong>: el prefijo de la cola (ej. "C",
      "P1"), el nombre visible y su ícono, si la numeración reinicia cada día o es continua, el
      rango de números permitido, un máximo opcional de turnos activos a la vez, y si acepta
      turnos sin cita previa desde front-desk/kiosco. Ahí también se marca un área como <strong>prioridad</strong> de otra (para embarazadas, adultos mayores, etc. — se llaman
      antes y solo se emiten desde Recepción). Archivar un área impide crear turnos nuevos ahí,
      pero no afecta los turnos ya emitidos.</p></section> <section class="svelte-37b9k6"><h2 id="configuracion" class="svelte-37b9k6">Configuración general</h2> <p class="svelte-37b9k6"><strong>Configuración del Ticket</strong>: el nombre de empresa que aparece impreso
      encima de "FLOW CONNECTED" en cada ticket físico.</p> <p class="svelte-37b9k6"><strong>Duración de Sesión</strong>: cuántas horas (entre 8 y 16) dura la sesión de un
      usuario de personal antes de pedirle iniciar sesión de nuevo; el kiosco puede
      configurarse para que su sesión nunca expire sola, ya que corre desatendido todo el día.</p> <p class="svelte-37b9k6"><strong>Reinserción de Turnos No-Show</strong>: hasta cuántos turnos pueden haberse
      llamado después de un No-Show para que ese turno todavía se pueda reinsertar en la cola
      (vea <a href="/docs/ventanilla" class="svelte-37b9k6">Ventanilla</a>). Los turnos que forman parte de una
      visita con varias áreas no cuentan con este límite.</p> <p class="svelte-37b9k6"><strong>Idiomas</strong>: activa o desactiva el selector de idioma (Español, Kreyòl
      Ayisyen, Inglés) en el login, el kiosco y las pantallas de turno. Con "Solo Español" el
      selector queda oculto en toda la aplicación.</p> <p class="svelte-37b9k6"><strong>Zona de Peligro — Reinicio de Fábrica</strong>: elimina todos los turnos,
      estaciones, módulos, kioscos, pizarras, prefijos de cola y cierres diarios, y reinicia
      los contadores desde 1. Los usuarios y roles se conservan. Es irreversible — pide escribir
      "RESET" y la contraseña del administrador para confirmar. Úselo solo para dejar el
      sistema limpio antes de empezar a usarlo en producción, nunca con datos reales de
      pacientes ya cargados.</p></section></article>`);function p(e,p){o(p,!1);let m=d(`administracion`);l();var h=f(),g=a(h),_=a(g),v=a(_,!0);i(_);var y=c(_);i(g),u(6),i(h),r(()=>{t(v,m.icon),t(y,` ${m.title??``}`)}),n(e,h),s()}export{p as component};