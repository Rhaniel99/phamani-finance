<?php

namespace App\Providers;

use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Repositories\ICategoryRepository;
use App\Interfaces\Repositories\IInstallmentRepository;
use App\Interfaces\Repositories\IRecurringTransactionRepository;
use App\Interfaces\Repositories\ITransactionRepository;
use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\IDashboardService;
use App\Interfaces\Services\IInstallmentService;
use App\Interfaces\Services\IRecurringTransactionService;
use App\Interfaces\Services\ITransactionService;
use App\Repositories\AccountRepository;
use App\Repositories\CategoryRepository;
use App\Repositories\InstallmentRepository;
use App\Repositories\RecurringTransactionRepository;
use App\Repositories\TransactionRepository;
use App\Services\AccountService;
use App\Services\CategoryService;
use App\Services\DashboardService;
use App\Services\InstallmentService;
use App\Services\RecurringTransactionService;
use App\Services\TransactionService;
use Illuminate\Support\ServiceProvider;

/**
 * Liga as interfaces (contratos) às implementações de Services e Repositories.
 */
class RepositoryServiceProvider extends ServiceProvider
{
    /**
     * @var array<class-string, class-string>
     */
    public array $bindings = [
        // Services
        IAccountService::class => AccountService::class,
        ICategoryService::class => CategoryService::class,
        IDashboardService::class => DashboardService::class,
        IInstallmentService::class => InstallmentService::class,
        IRecurringTransactionService::class => RecurringTransactionService::class,
        ITransactionService::class => TransactionService::class,

        // Repositories
        IAccountRepository::class => AccountRepository::class,
        ICategoryRepository::class => CategoryRepository::class,
        IInstallmentRepository::class => InstallmentRepository::class,
        IRecurringTransactionRepository::class => RecurringTransactionRepository::class,
        ITransactionRepository::class => TransactionRepository::class,
    ];
}
