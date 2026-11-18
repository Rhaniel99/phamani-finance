<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

class DashboardTest extends TestCase
{
    use RefreshDatabase;

    public function test_dashboard_renders_with_financial_props(): void
    {
        $user = User::factory()->create();
        app(IAccountService::class)->createDefaultForUser($user->id);
        app(ICategoryService::class)->createDefaultsForUser($user->id);

        $this->actingAs($user)
            ->get(route('dashboard', ['period' => 'monthly']))
            ->assertOk()
            ->assertInertia(fn (Assert $page) => $page
                ->component('dashboard')
                ->where('period', 'monthly')
                ->has('kpis')
                ->has('cashFlow', now()->daysInMonth)
                ->has('categoryPie')
                ->has('accounts', 1)
                ->has('categories', 7)
                ->has('recentTransactions')
            );
    }

    public function test_transactions_page_renders(): void
    {
        $this->actingAs(User::factory()->create())
            ->get(route('transactions.index'))
            ->assertOk()
            ->assertInertia(fn (Assert $page) => $page
                ->component('transactions/index')
                ->has('transactions.data')
            );
    }
}
