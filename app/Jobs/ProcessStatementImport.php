<?php

namespace App\Jobs;

use App\Interfaces\Services\IStatementImportService;
use App\Models\StatementImport;
use Illuminate\Foundation\Bus\Dispatchable;

/**
 * OCR do extrato. Disparado com dispatchAfterResponse: roda no mesmo processo do PHP-FPM
 * logo depois que a resposta do upload é enviada (sem precisar de worker de fila).
 */
class ProcessStatementImport
{
    use Dispatchable;

    public function __construct(public string $importId) {}

    public function handle(IStatementImportService $imports): void
    {
        $import = StatementImport::query()->find($this->importId);

        if ($import !== null && $import->status === 'queued') {
            $imports->process($import);
        }
    }
}
