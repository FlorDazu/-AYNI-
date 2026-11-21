import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { Router } from '@angular/router';
import { fEntero, fSoles } from '../../../core/formato';
import { mensajeDeError } from '../../../core/error-api';
import type { Kpis, Ubigeo } from '../../../core/models';
import { PublicService } from '../../../core/services/public.service';

/** HU-01 · Portal principal con indicadores de impacto y buscador por distrito. */
@Component({
  selector: 'app-landing',
  imports: [FormsModule, RouterLink],
  templateUrl: './landing.html',
})
export class Landing implements OnInit {
  private readonly publico = inject(PublicService);
  private readonly router = inject(Router);

  readonly fEntero = fEntero;
  readonly fSoles = fSoles;

  kpis = signal<Kpis | null>(null);
  cargando = signal(true);
  error = signal('');

  private ubigeos: Ubigeo[] = [];
  departamentos: string[] = [];
  provincias: string[] = [];
  distritos: string[] = [];

  departamentoSel = '';
  provinciaSel = '';
  distritoSel = '';

  ngOnInit(): void {
    this.publico.kpis().subscribe({
      next: (kpis) => {
        this.kpis.set(kpis);
        this.cargando.set(false);
      },
      error: (err) => {
        this.error.set(mensajeDeError(err));
        this.cargando.set(false);
      },
    });

    this.publico.ubigeos().subscribe({
      next: (ubigeos) => {
        this.ubigeos = ubigeos;
        this.departamentos = this.unicos(ubigeos.map((u) => u.departamento));
      },
      error: () => {
        /* el buscador sigue funcionando sin catálogo */
      },
    });
  }

  alCambiarDepartamento(): void {
    this.provinciaSel = '';
    this.distritoSel = '';
    this.refrescarListas();
  }

  alCambiarProvincia(): void {
    this.distritoSel = '';
    this.refrescarListas();
  }

  buscar(): void {
    this.router.navigate(['/ollas'], {
      queryParams: {
        departamento: this.departamentoSel,
        provincia: this.provinciaSel,
        distrito: this.distritoSel,
      },
    });
  }

  private refrescarListas(): void {
    const porDepartamento = this.departamentoSel
      ? this.ubigeos.filter((u) => u.departamento === this.departamentoSel)
      : this.ubigeos;
    this.provincias = this.unicos(porDepartamento.map((u) => u.provincia));
    const porProvincia = this.provinciaSel
      ? porDepartamento.filter((u) => u.provincia === this.provinciaSel)
      : porDepartamento;
    this.distritos = this.unicos(porProvincia.map((u) => u.distrito));
  }

  private unicos(valores: string[]): string[] {
    return [...new Set(valores)].sort((a, b) => a.localeCompare(b, 'es'));
  }
}
