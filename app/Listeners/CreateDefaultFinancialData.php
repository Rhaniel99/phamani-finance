<?php

namespace App\Listeners;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Models\User;
use Illuminate\Auth\Events\Registered;

/**
 * Ao criar um usuário, gera a conta "Carteira" e as categorias padrão.
 * (Substitui o UserObserver do Lukisa.)
 */
class CreateDefaultFinancialData
{
    public function __construct(
        protected IAccountService $accounts,
        protected ICategoryService $categories,
    ) {}

    public function handle(Registered $event): void
    {
        /** @var User $user */
        $user = $event->user;

        $this->accounts->createDefaultForUser($user->id);
        $this->categories->createDefaultsForUser($user->id);
    }
}
