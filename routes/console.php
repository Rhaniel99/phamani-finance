<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Fase 1: lança recorrências vencidas e aplica no saldo o que chegou na data.
// Roda a cada hora: a execução da meia-noite (fuso do APP_TIMEZONE) já pega o que venceu no dia.
Schedule::command('phamani:process-due')->hourly()->withoutOverlapping();
