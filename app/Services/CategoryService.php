<?php

namespace App\Services;

use App\DTOs\Category\StoreCategoryData;
use App\Enums\Category\Color;
use App\Enums\Category\Icon;
use App\Interfaces\Repositories\ICategoryRepository;
use App\Interfaces\Services\ICategoryService;
use App\Models\Category;
use Illuminate\Support\Collection;

class CategoryService implements ICategoryService
{
    /**
     * Categorias criadas para todo usuário novo.
     *
     * @var list<array{name: string, type: string, icon: Icon, color: Color}>
     */
    private const array DEFAULTS = [
        ['name' => 'Alimentação', 'type' => 'expense', 'icon' => Icon::UTENSILS, 'color' => Color::ORANGE],
        ['name' => 'Transporte', 'type' => 'expense', 'icon' => Icon::CAR, 'color' => Color::BLUE],
        ['name' => 'Lazer', 'type' => 'expense', 'icon' => Icon::GAMEPAD, 'color' => Color::PURPLE],
        ['name' => 'Saúde', 'type' => 'expense', 'icon' => Icon::HEART, 'color' => Color::RED],
        ['name' => 'Salário', 'type' => 'income', 'icon' => Icon::WALLET, 'color' => Color::GREEN],
        ['name' => 'Freelance', 'type' => 'income', 'icon' => Icon::BRIEFCASE, 'color' => Color::TEAL],
        ['name' => 'Outros', 'type' => 'both', 'icon' => Icon::TAG, 'color' => Color::SLATE],
    ];

    public function __construct(
        protected ICategoryRepository $repository,
    ) {}

    public function listForUser(string $userId): Collection
    {
        return $this->repository
            ->query()
            ->where('user_id', $userId)
            ->orderBy('name')
            ->get(['id', 'name', 'type', 'color', 'icon']);
    }

    public function create(string $userId, StoreCategoryData $dto): Category
    {
        /** @var Category */
        return $this->repository->create([
            'user_id' => $userId,
            'parent_id' => $dto->parent_id,
            'name' => $dto->name,
            'type' => $dto->type,
            'color' => $dto->color->value,
            'icon' => $dto->icon->value,
        ]);
    }

    public function createDefaultsForUser(string $userId): void
    {
        foreach (self::DEFAULTS as $category) {
            $this->repository->query()->firstOrCreate(
                ['user_id' => $userId, 'name' => $category['name']],
                [
                    'type' => $category['type'],
                    'icon' => $category['icon']->value,
                    'color' => $category['color']->value,
                ],
            );
        }
    }
}
