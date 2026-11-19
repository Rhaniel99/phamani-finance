<?php

namespace App\Console\Commands;

use App\Interfaces\Services\IShareService;
use App\Models\Contact;
use Illuminate\Console\Command;

/**
 * Compartilha, com contatos já vinculados, as divisões do mês atual em diante.
 * Útil para divisões lançadas antes do convite ser aceito. Pode rodar várias vezes (idempotente).
 */
class ShareUpcomingWithLinkedContacts extends Command
{
    protected $signature = 'phamani:share-upcoming';

    protected $description = 'Envia para contatos vinculados as divisões do mês atual em diante que ainda não foram compartilhadas.';

    public function handle(IShareService $shares): int
    {
        $total = 0;

        Contact::query()->whereNotNull('linked_user_id')->each(function (Contact $contact) use ($shares, &$total) {
            $total += $shares->shareUpcomingWith($contact);
        });

        $this->info("Transações verificadas: {$total}.");

        return self::SUCCESS;
    }
}
