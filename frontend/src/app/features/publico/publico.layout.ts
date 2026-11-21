import { Component, inject } from '@angular/core';
import { RouterLink, RouterOutlet } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';

/** Envoltorio del portal público: cabecera, contenido y pie. */
@Component({
  selector: 'app-publico-layout',
  imports: [RouterOutlet, RouterLink],
  templateUrl: './publico.layout.html',
})
export class PublicoLayout {
  readonly auth = inject(AuthService);
}
