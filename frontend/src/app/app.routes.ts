import { Routes } from '@angular/router';
import { authGuard, roleGuard } from './core/auth.guard';
import { PublicoLayout } from './features/publico/publico.layout';
import { Landing } from './features/publico/landing/landing';
import { DirectorioOllas } from './features/publico/ollas/ollas';
import { OllaDetalle } from './features/publico/olla-detalle/olla-detalle';
import { RegistroPublico } from './features/publico/registro-publico/registro-publico';
import { Login } from './features/auth/login/login';
import { Registro } from './features/auth/registro/registro';
import { PanelLayout } from './features/panel/panel.layout';
import { MiOlla } from './features/panel/mi-olla/mi-olla';
import { Inventario } from './features/panel/inventario/inventario';
import { Donaciones } from './features/panel/donaciones/donaciones';
import { Recetas } from './features/panel/recetas/recetas';
import { Reportes } from './features/panel/reportes/reportes';
import { OllasAdmin } from './features/admin/ollas-admin/ollas-admin';
import { UsuariosAdmin } from './features/admin/usuarios-admin/usuarios-admin';
import { Auditoria } from './features/admin/auditoria/auditoria';

export const routes: Routes = [
  // ---------------------------------------------------------------- portal público
  {
    path: '',
    component: PublicoLayout,
    children: [
      { path: '', component: Landing, title: 'AYNI · Ollas comunes' },
      { path: 'ollas', component: DirectorioOllas, title: 'Ollas comunes · AYNI' },
      { path: 'ollas/:id', component: OllaDetalle, title: 'Ficha de olla · AYNI' },
      { path: 'registrar-olla', component: RegistroPublico, title: 'Registrar olla · AYNI' },
      { path: 'login', component: Login, title: 'Iniciar sesión · AYNI' },
      { path: 'registro', component: Registro, title: 'Crear cuenta de dirigenta · AYNI' },
    ],
  },

  // ------------------------------------------------------------ panel de la dirigenta
  {
    path: 'panel',
    component: PanelLayout,
    canActivate: [authGuard, roleGuard],
    data: { roles: ['DIRIGENTA'] },
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'mi-olla' },
      { path: 'mi-olla', component: MiOlla, title: 'Mi olla · AYNI' },
      { path: 'inventario', component: Inventario, title: 'Inventario PEPS · AYNI' },
      { path: 'donaciones', component: Donaciones, title: 'Donantes y donaciones · AYNI' },
      { path: 'recetas', component: Recetas, title: 'Recetas y despacho · AYNI' },
      { path: 'reportes', component: Reportes, title: 'Kardex y reportes · AYNI' },
    ],
  },

  // ------------------------------------------------------------- panel del administrador
  {
    path: 'admin',
    component: PanelLayout,
    canActivate: [authGuard, roleGuard],
    data: { roles: ['ADMIN'] },
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'ollas' },
      { path: 'ollas', component: OllasAdmin, title: 'Gestión de ollas · AYNI' },
      { path: 'usuarios', component: UsuariosAdmin, title: 'Gestión de usuarios · AYNI' },
      { path: 'auditoria', component: Auditoria, title: 'Auditoría por olla · AYNI' },
    ],
  },

  { path: '**', redirectTo: '' },
];
