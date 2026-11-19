<?php

namespace App\Console\Commands;

use App\Interfaces\Services\IBalanceService;
use App\Interfaces\Services\IPaymentService;
use App\Interfaces\Services\IRecurringTransactionService;
use Illuminate\Console\Command;

class ProcessDueTransactions extends Command
{
    protected $signature = 'phamani:process-due';

    protected $description = 'Lança as recorrências vencidas (com o último valor), paga as de débito automático e aplica no saldo o que já está pago.';

    public function handle(IRecurringTransactionService $recurring, IPaymentService $payments, IBalanceService $balance): int
    {
        $created = $recurring->generateAllDue();
        $autoPaid = $payments->processAutoPay();
        $applied = $balance->applyAllDue();

        $this->info("Ocorrências lançadas: {$created}. Pagas por débito automático: {$autoPaid}. Verificadas no saldo: {$applied}.");

        return self::SUCCESS;
    }
}
