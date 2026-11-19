<?php

namespace App\Interfaces\Services;

use App\Models\Contact;
use App\Models\Share;
use App\Models\Transaction;
use App\Models\User;

interface IShareService
{
    /**
     * Chamado sempre que a divisão de uma transação é gravada:
     * cria pedidos para contatos vinculados, atualiza cópias aceitas e remove quem saiu da divisão.
     */
    public function syncFor(Transaction $source): void;

    /**
     * Compartilha com um contato recém-vinculado as divisões do mês atual em diante
     * (ex.: as próximas parcelas de um parcelamento lançado antes do convite).
     * Divisões de meses anteriores ficam só como registro. Retorna quantas transações foram verificadas.
     */
    public function shareUpcomingWith(Contact $contact): int;

    /**
     * Remove as cópias (antes de excluir a transação original).
     */
    public function removeFor(Transaction $source): void;

    /**
     * Aceita a série inteira: cria as cópias no sistema de quem recebeu.
     */
    public function accept(Share $share, User $user, string $categoryId, ?string $accountId): void;

    public function decline(Share $share, User $user): void;

    /**
     * Sai de uma divisão já aceita: as cópias somem do seu sistema.
     */
    public function leave(Share $share, User $user): void;

    /**
     * Pedidos pendentes para o usuário, já resumidos para a tela de Pendências.
     *
     * @return list<array<string, mixed>>
     */
    public function pendingFor(User $user): array;

    /**
     * Pedidos aceitos pelo usuário (para poder sair da divisão).
     *
     * @return list<array<string, mixed>>
     */
    public function acceptedFor(User $user): array;
}
