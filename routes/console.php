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

// Importações de extrato esquecidas (não lançadas em 14 dias): apaga, com os arquivos que sobraram.
Schedule::call(function () {
    \App\Models\StatementImport::query()
        ->where('status', '!=', 'done')
        ->where('created_at', '<', now()->subDays(14))
        ->get()
        ->each(fn ($import) => app(\App\Interfaces\Services\IStatementImportService::class)->discard($import));
})->daily()->name('phamani:prune-imports')->withoutOverlapping();
