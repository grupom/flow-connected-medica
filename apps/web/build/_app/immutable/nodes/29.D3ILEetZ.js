import{I as e,N as t,P as n,Y as r,bt as i,et as a,gt as o,ht as s,nt as c,s as l,yt as u}from"../chunks/BYdMN7ig.js";import"../chunks/xihTtKlq.js";import"../chunks/DS_t55_M.js";import{n as d}from"../chunks/jftPeae2.js";var f=e(`<article class="doc-page svelte-yd1n3w"><h1 class="svelte-yd1n3w"><span class="doc-icon svelte-yd1n3w"> </span> </h1> <section class="svelte-yd1n3w"><h2 id="tableros" class="svelte-yd1n3w">Tableros de pantalla</h2> <p class="svelte-yd1n3w">La pantalla pública muestra en tiempo real los turnos que están siendo llamados y los
      últimos atendidos, para que el paciente sepa cuándo le toca sin tener que preguntar.
      Cada llamado también se anuncia por voz, además de mostrarse en grande en pantalla.</p> <p class="svelte-yd1n3w">Desde <strong>Pantallas</strong> (menú principal) se crea un tablero — nombre, código,
      idioma de la voz, tono del timbre — y se le asignan las estaciones que va a mostrar.
      Opcionalmente se le puede subir publicidad (un video o una secuencia de imágenes) que
      rota mientras no hay llamados nuevos; si llega un turno mientras se muestra la
      publicidad, la pantalla la interrumpe automáticamente para mostrar el llamado y luego
      retoma la publicidad donde había quedado.</p> <p class="svelte-yd1n3w">Cada tablero tiene su propia dirección (ej. <code class="svelte-yd1n3w">/board/CODIGO</code>) para abrir en
      el televisor de la sala de espera correspondiente.</p></section> <section class="svelte-yd1n3w"><h2 id="kiosco" class="svelte-yd1n3w">Kiosco de autoservicio</h2> <p class="svelte-yd1n3w">El kiosco deja que el paciente saque su propio turno sin pasar por recepción. Cada
      terminal inicia sesión con una cuenta de kiosco propia, configurada en <a href="/docs/administracion" class="svelte-yd1n3w">Administración</a>, que solo tiene acceso a las áreas
      que se le asignaron — nunca a las áreas marcadas como prioridad, que solo se emiten
      desde <a href="/docs/recepcion" class="svelte-yd1n3w">Recepción</a>.</p> <p class="svelte-yd1n3w">El paciente toca el área que necesita, el turno se imprime automáticamente, y la
      pantalla vuelve sola a la selección de áreas después de unos segundos. Si el sistema
      tiene más de un idioma habilitado, aparece un selector arriba para que el paciente
      elija el suyo.</p></section></article>`);function p(e,p){o(p,!1);let m=d(`pantallas-kiosco`);l();var h=f(),g=a(h),_=a(g),v=a(_,!0);i(_);var y=c(_);i(g),u(4),i(h),r(()=>{t(v,m.icon),t(y,` ${m.title??``}`)}),n(e,h),s()}export{p as component};