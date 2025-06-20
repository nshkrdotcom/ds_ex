defmodule ElixirML.ResourceTest do
  use ExUnit.Case, async: true

  # Test resource definition
  defmodule TestResource do
    use ElixirML.Resource

    attributes do
      attribute(:name, :string, allow_nil?: false)
      attribute(:type, :atom, constraints: [one_of: [:test, :example]])
      attribute(:config, :map, default: %{})
    end

    relationships do
      belongs_to(:parent, TestResource)
      has_many(:children, TestResource)
    end

    actions do
      action :test_action do
        argument(:input, :string, allow_nil?: false)
      end
    end

    calculations do
      calculate(:test_calc, :integer, ElixirML.ResourceTest.TestCalculation)
    end
  end

  defmodule TestCalculation do
    def calculate(_resource, _args), do: {:ok, 42}
  end

  describe "Resource behaviour" do
    test "resource can be defined with attributes and relationships" do
      # Test that we can define a basic resource structure
      assert TestResource.__resource_attributes__() |> length() == 3
      assert TestResource.__resource_relationships__() |> length() == 2
    end

    test "resource supports schema integration" do
      # Test schema-based attribute definitions - placeholder for now
      assert true
    end

    test "resource supports variable extraction" do
      # Test automatic variable extraction from attributes - placeholder for now
      assert true
    end
  end

  describe "Resource CRUD operations" do
    test "resource can be created with valid attributes" do
      {:ok, resource} =
        TestResource.create(%{
          name: "test_resource",
          type: :test,
          config: %{key: "value"}
        })

      assert resource.name == "test_resource"
      assert resource.type == :test
      assert resource.config == %{key: "value"}
    end

    test "resource creation validates required attributes" do
      {:error, reason} = TestResource.create(%{type: :test})
      assert reason == {:validation_error, :name, "name cannot be nil"}
    end

    test "resource creation validates constraints" do
      {:error, reason} =
        TestResource.create(%{
          name: "test",
          type: :invalid
        })

      assert reason == {:validation_error, :type, "type must be one of [:test, :example]"}
    end
  end

  describe "Resource actions" do
    test "resource can execute actions" do
      {:ok, resource} =
        TestResource.create(%{
          name: "test",
          type: :test
        })

      {:ok, result} = TestResource.execute_action(resource, :test_action, %{input: "test"})
      assert result.action == :test_action
      assert result.status == :executed
    end

    test "resource returns error for unknown actions" do
      {:ok, resource} = TestResource.create(%{name: "test", type: :test})

      {:error, reason} = TestResource.execute_action(resource, :unknown_action, %{})
      assert reason == :action_not_found
    end
  end

  describe "Resource calculations" do
    test "resource can execute calculations" do
      {:ok, resource} =
        TestResource.create(%{
          name: "test",
          type: :test
        })

      {:ok, result} = TestResource.calculate(resource, :test_calc, %{})
      assert result == 42
    end

    test "resource returns error for unknown calculations" do
      {:ok, resource} = TestResource.create(%{name: "test", type: :test})

      {:error, reason} = TestResource.calculate(resource, :unknown_calc, %{})
      assert reason == :calculation_not_found
    end
  end

  describe "Resource relationships" do
    test "resource can access belongs_to relationships" do
      {:ok, resource} = TestResource.create(%{name: "test", type: :test})

      {:ok, parent} = TestResource.get_parent(resource)
      assert parent == nil
    end

    test "resource can access has_many relationships" do
      {:ok, resource} = TestResource.create(%{name: "test", type: :test})

      {:ok, children} = TestResource.get_children(resource)
      assert children == []
    end
  end

  describe "Resource validation" do
    test "resource can be validated" do
      {:ok, resource} = TestResource.create(%{name: "test", type: :test})

      {:ok, validated} = TestResource.validate(resource)
      assert validated == resource
    end

    test "resource validation catches invalid data" do
      # Create a resource with invalid data directly
      invalid_resource = %TestResource{name: nil, type: :invalid}

      {:error, reason} = TestResource.validate(invalid_resource)
      # Validation may catch the first invalid field it encounters
      assert match?({:validation_error, _, _}, reason)
    end
  end
end
