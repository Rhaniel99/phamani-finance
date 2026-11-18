<?php

namespace Database\Seeders;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Models\User;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    /**
     * Cria um usuário de demonstração com conta e categorias padrão.
     * Em ambiente real os usuários são criados pelo login com Google.
     */
    public function run(IAccountService $accounts, ICategoryService $categories): void
    {
        $user = User::factory()->create([
            'name' => 'Usuário Demo',
            'email' => 'demo@phamani.test',
        ]);

        $accounts->createDefaultForUser($user->id);
        $categories->createDefaultsForUser($user->id);
    }
}
