<?php

namespace App\Providers;

use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Repositories\ICategoryRepository;
use App\Interfaces\Repositories\IContactRepository;
use App\Interfaces\Repositories\IInstallmentRepository;
use App\Interfaces\Repositories\IRecurringTransactionRepository;
use App\Interfaces\Repositories\ITransactionRepository;
use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\IBalanceService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\IContactService;
use App\Interfaces\Services\ICreditCardService;
use App\Interfaces\Services\IDashboardService;
use App\Interfaces\Services\IInstallmentService;
use App\Interfaces\Services\IInvitationService;
use App\Interfaces\Services\IPaymentService;
use App\Interfaces\Services\IRecurringTransactionService;
use App\Interfaces\Services\IShareService;
use App\Interfaces\Services\ISplitService;
use App\Interfaces\Services\ITransactionService;
use App\Repositories\AccountRepository;
use App\Repositories\CategoryRepository;
use App\Repositories\ContactRepository;
use App\Repositories\InstallmentRepository;
use App\Repositories\RecurringTransactionRepository;
use App\Repositories\TransactionRepository;
use App\Services\AccountService;
use App\Services\BalanceService;
use App\Services\CategoryService;
use App\Services\ContactService;
use App\Services\CreditCardService;
use App\Services\DashboardService;
use App\Services\InstallmentService;
use App\Services\InvitationService;
use App\Services\PaymentService;
use App\Services\RecurringTransactionService;
use App\Services\ShareService;
use App\Services\SplitService;
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
        IBalanceService::class => BalanceService::class,
        ICategoryService::class => CategoryService::class,
        IContactService::class => ContactService::class,
        ICreditCardService::class => CreditCardService::class,
        IDashboardService::class => DashboardService::class,
        IInstallmentService::class => InstallmentService::class,
        IInvitationService::class => InvitationService::class,
        IPaymentService::class => PaymentService::class,
        IRecurringTransactionService::class => RecurringTransactionService::class,
        IShareService::class => ShareService::class,
        ISplitService::class => SplitService::class,
        ITransactionService::class => TransactionService::class,

        // Repositories
        IAccountRepository::class => AccountRepository::class,
        ICategoryRepository::class => CategoryRepository::class,
        IContactRepository::class => ContactRepository::class,
        IInstallmentRepository::class => InstallmentRepository::class,
        IRecurringTransactionRepository::class => RecurringTransactionRepository::class,
        ITransactionRepository::class => TransactionRepository::class,
    ];
}
